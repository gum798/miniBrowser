import SwiftUI
import WebKit
import MiniBrowserCore

struct WebView: NSViewRepresentable {
    @ObservedObject var tab: Tab
    let model: TabsModel
    /// Called when a navigation finishes, for history recording: (url, title).
    var onCommit: (URL, String) -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(model: model, onCommit: onCommit)
        coordinator.tab = tab
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(tab.webView, to: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.model = model
        context.coordinator.onCommit = onCommit
        context.coordinator.tab = tab
        if container.subviews.first !== tab.webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(tab.webView, to: container, coordinator: context.coordinator)
            tab.reattachLoad()   // load the URL on a freshly recreated web view (hardReset)
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        container.subviews.forEach { $0.removeFromSuperview() }   // detach, never dealloc
    }

    private func attach(_ webView: WKWebView, to container: NSView, coordinator: Coordinator) {
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        // A view coming back from the page stack may carry a stale swipe transform.
        webView.layer?.setAffineTransform(.identity)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let swipe = EdgeSwipeOverlay()   // mouse edge-drag = back/forward (on top of the web view)
        swipe.tab = coordinator.tab
        swipe.frame = container.bounds
        swipe.autoresizingMask = [.width, .height]
        container.addSubview(swipe)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var model: TabsModel?
        var onCommit: (URL, String) -> Void
        weak var tab: Tab?
        init(model: TabsModel, onCommit: @escaping (URL, String) -> Void) {
            self.model = model
            self.onCommit = onCommit
        }

        // target=_blank / window.open -> new tab. Reuse the PASSED config; return its web view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let model else { return nil }
            let tab = model.newTab(configuration: configuration)
            return tab.webView   // WebKit drives the load; preserves window.opener
        }

        // Link clicks load into a NEW web view so the current page stays alive on
        // the tab's page stack — going back is then instant (no reload). Fragment
        // jumps, non-web schemes, new-window targets (targetFrame == nil -> handled
        // by createWebViewWith) and the very first page stay in this web view.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if let tab,
               navigationAction.navigationType == .linkActivated,
               navigationAction.targetFrame?.isMainFrame == true,
               webView === tab.webView,                    // not a stacked background page
               tab.url != nil,                             // not the tab's very first load
               let url = navigationAction.request.url,
               LinkNavigation.shouldStack(url: url, currentURL: webView.url) {
                decisionHandler(.cancel)
                tab.pushNewPage(loading: url)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === tab?.webView else { return }   // a stacked background page finished — ignore
            tab?.loadError = nil   // clear stale overlay (covers in-page links, goBack/goForward)
            if tab?.inverted == true { tab?.applyInvert() }   // re-apply invert on the new document
            ElementHider.shared.onPageLoaded(webView)         // re-hide remembered elements / re-arm picker
            // Detect garbage (EUC-KR mojibake, or a raw HTTP response shown as text after
            // a connection desync) and auto-recover. The probe returns the replacement-char
            // ratio, whether any are present, and a prefix of the body for signature checks.
            webView.evaluateJavaScript(
                "(function(){var t=(document.body&&document.body.innerText)||'';" +
                "if(t.length<200)return JSON.stringify({ratio:0,repl:false,head:''});" +
                "var n=0;for(var i=0;i<t.length;i++){if(t.charCodeAt(i)===65533)n++;}" +
                "return JSON.stringify({ratio:n/t.length,repl:n>0,head:t.slice(0,400)});})()"
            ) { [weak tab] result, _ in
                guard let json = result as? String, let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                let garbled = PageGarble.isGarbled(
                    replacementRatio: obj["ratio"] as? Double ?? 0,
                    hasReplacementChar: obj["repl"] as? Bool ?? false,
                    bodyPrefix: obj["head"] as? String ?? "")
                tab?.handleLoaded(garbled: garbled)
            }
            if let url = webView.url {
                onCommit(url, webView.title ?? "")
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error, on: webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error, on: webView)
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            FileHandle.standardError.write(Data("WebContent process terminated — reloading (G2)\n".utf8))
            if webView === tab?.webView {
                webView.reloadFromOrigin()   // re-fetch fresh so encoding/state is re-derived, not restored stale
            } else {
                tab?.backgroundPageDied(webView)   // demote to placeholder; reloads when shown
            }
        }
        private func report(_ error: Error, on webView: WKWebView) {
            FileHandle.standardError.write(Data("nav failed: \(error)\n".utf8))
            guard webView === tab?.webView else { return }               // background page — no overlay
            if (error as NSError).code == NSURLErrorCancelled { return }  // -999: stop()/redirects
            tab?.loadError = error.localizedDescription
        }
    }
}
