import SwiftUI
import WebKit

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab?.loadError = nil   // clear stale overlay (covers in-page links, goBack/goForward)
            if tab?.inverted == true { tab?.applyInvert() }   // re-apply invert on the new document
            ElementHider.shared.onPageLoaded(webView)         // re-hide remembered elements / re-arm picker
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
            webView.reload()
        }
        private func report(_ error: Error, on webView: WKWebView) {
            FileHandle.standardError.write(Data("nav failed: \(error)\n".utf8))
            if (error as NSError).code == NSURLErrorCancelled { return }  // -999: stop()/redirects
            tab?.loadError = error.localizedDescription
        }
    }
}
