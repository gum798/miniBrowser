import Foundation
import WebKit
import Combine
import MiniBrowserCore

@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String = ""
    @Published var url: URL?
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var zoom: Double = PageZoom.standard
    @Published var inverted = false

    private var kvo: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = MobileUserAgent.iPhoneSafari   // G3: before any load
        webView.allowsBackForwardNavigationGestures = true       // two-finger swipe = back/forward
        observe()
        AdBlocker.shared.register(webView)                       // iPhone-Safari-style ad blocking
    }

    private func observe() {
        // KVO for continuous/derived state -> @Published. WKWebView KVO fires
        // synchronously on the main thread, so we read the Sendable new value
        // out of the change and apply it on the main actor (assumeIsolated).
        kvo = [
            webView.observe(\.title, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? nil
                MainActor.assumeIsolated { self?.title = value ?? "" }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? nil
                MainActor.assumeIsolated { self?.url = value }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? 0
                MainActor.assumeIsolated { self?.progress = value }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                MainActor.assumeIsolated { self?.canGoBack = value }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                MainActor.assumeIsolated { self?.canGoForward = value }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                MainActor.assumeIsolated { self?.isLoading = value }
            },
        ]
    }

    func load(_ url: URL) {
        loadError = nil
        webView.load(URLRequest(url: url))
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { loadError = nil; webView.reload() }
    func stop() { webView.stopLoading() }

    // Font/page zoom — pageZoom is a property of the web view, so it persists
    // across navigations automatically; we just track the level for the UI.
    func zoomIn()    { setZoom(PageZoom.stepped(zoom, by: 1)) }
    func zoomOut()   { setZoom(PageZoom.stepped(zoom, by: -1)) }
    func resetZoom() { setZoom(PageZoom.standard) }
    private func setZoom(_ z: Double) {
        zoom = z
        webView.pageZoom = z
    }

    // Color inversion (dark-mode-ish): inject/remove a CSS filter. Re-applied
    // after each page load via `applyInvert()` from the navigation delegate.
    func toggleInvert() {
        inverted.toggle()
        installInvertScript()   // applies to every future load, from the first paint
        applyInvert()           // and to the page already on screen
    }
    /// Inject the invert style at document start so the page stays inverted
    /// throughout loading and across navigations (no flash of original colors).
    private func installInvertScript() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        guard inverted else { return }
        ucc.addUserScript(WKUserScript(source: Self.invertScript(true),
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
    }
    func applyInvert() {
        webView.evaluateJavaScript(Self.invertScript(inverted))
    }
    private static func invertScript(_ on: Bool) -> String {
        on ? """
        (function(){var d=document,id='__mb_invert__',s=d.getElementById(id);
        if(!s){s=d.createElement('style');s.id=id;
        s.textContent='html{filter:invert(1) hue-rotate(180deg) !important;background:#fafafa !important}'
        +'img,picture,video,canvas,iframe,svg,[style*=\\"background-image\\"]{filter:invert(1) hue-rotate(180deg) !important}';
        (d.head||d.documentElement).appendChild(s);}})();
        """ : "(function(){var s=document.getElementById('__mb_invert__');if(s)s.remove();})();"
    }

    deinit { kvo.forEach { $0.invalidate() } }   // G4: prevent crashes/leaks
}
