import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    @ObservedObject var tab: Tab
    /// Called when a navigation finishes, for history recording: (url, title).
    var onCommit: (URL, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(tab.webView, to: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.onCommit = onCommit
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
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCommit: (URL, String) -> Void
        init(onCommit: @escaping (URL, String) -> Void) { self.onCommit = onCommit }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
        }
    }
}
