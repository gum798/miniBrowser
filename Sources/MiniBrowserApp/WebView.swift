import SwiftUI
import WebKit

struct SmokeWebView: NSViewRepresentable {
    let urlString: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        // G3: mobile UA must be set BEFORE loading.
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        // G2 diagnostics: if the WebContent process dies, the bundle metadata is wrong.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            FileHandle.standardError.write(Data("nav failed: \(error)\n".utf8))
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            FileHandle.standardError.write(Data("WebContent process terminated — check .app bundle metadata (G2)\n".utf8))
        }
    }
}
