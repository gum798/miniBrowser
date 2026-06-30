import Foundation
import WebKit
import Combine
import MiniBrowserCore

@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    private(set) var webView: WKWebView   // recreated by hardReset()

    @Published var title: String = ""
    @Published var url: URL?
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var zoom: Double = PageZoom.standard
    @Published var inverted = false

    /// A restored URL, loaded lazily the first time this tab becomes active
    /// (so background tabs don't load detached, which loses the load).
    var pendingURL: URL?

    private var kvo: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        webView = Self.makeWebView(configuration)
        observe()
        AdBlocker.shared.register(webView)                       // iPhone-Safari-style ad blocking
        ElementHider.shared.register(webView)                    // user-picked "방해 요소 가리기"
    }

    private static func makeWebView(_ configuration: WKWebViewConfiguration) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.customUserAgent = MobileUserAgent.iPhoneSafari   // G3: before any load
        wv.allowsBackForwardNavigationGestures = true       // two-finger swipe = back/forward
        return wv
    }

    private var recoverAttempts = 0          // bounds auto-recovery so we never loop forever
    private var reattachDelay: Double = 0    // delay before reattachLoad() fires (recovery uses one)
    private static let maxRecoverAttempts = 2

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

    /// Restore persisted per-tab state (zoom + color inversion). The URL is set
    /// separately as `pendingURL` and loaded on first activation.
    func applyRestored(zoom: Double, inverted: Bool) {
        self.zoom = zoom
        webView.pageZoom = zoom
        self.inverted = inverted
        if inverted { installInvertScript() }
    }

    /// Load the restored URL the first time the tab is shown.
    func loadPendingIfNeeded() {
        guard let pendingURL, url == nil else { return }
        self.pendingURL = nil
        load(pendingURL)
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    // Hard reload (re-fetch from origin, not cache) so a long-lived web view that
    // got into a bad text-decoding state recovers instead of re-rendering it stale.
    // Re-arms auto-recovery so a manual retry restarts the whole budget.
    func reload() { loadError = nil; recoverAttempts = 0; webView.reloadFromOrigin() }
    func stop() { webView.stopLoading() }

    /// Manual "강제 리셋": clear caches + rebuild the web view, and re-arm the
    /// auto-recovery budget so the user's deliberate retry starts fresh.
    func hardReset() {
        recoverAttempts = 0
        loadError = nil
        recover()
    }

    /// Recover a tab showing garbage (EUC-KR mojibake, or a raw HTTP response left
    /// over from a keep-alive connection desync). Clears the HTTP caches — keeping
    /// cookies/login — then recreates the web view (a fresh WebContent process) and
    /// reloads after a short delay so WebKit drops the poisoned pooled connection.
    private func recover() {
        let target = webView.url ?? pendingURL
        let store = webView.configuration.websiteDataStore
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache,
        ]
        store.removeData(ofTypes: cacheTypes, modifiedSince: .distantPast) {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.rebuildWebView(loading: target, afterDelay: 1.2) }
            }
        }
    }

    /// Swap in a brand-new web view, preserving zoom/inversion; back/forward history
    /// is reset. The load is deferred (see `reattachLoad`) so it happens once the new
    /// view is mounted; `delay` additionally lets a wedged connection age out.
    private func rebuildWebView(loading target: URL?, afterDelay delay: Double) {
        kvo.forEach { $0.invalidate() }; kvo = []
        webView = Self.makeWebView(WKWebViewConfiguration())
        observe()
        AdBlocker.shared.register(webView)
        ElementHider.shared.register(webView)
        webView.pageZoom = zoom
        if inverted { installInvertScript() }
        pendingURL = target           // loaded by reattachLoad() once the new view attaches
        reattachDelay = delay
        objectWillChange.send()       // swap the new web view into the view hierarchy
    }

    /// Load the pending URL on a web view that was just (re)attached — used after a
    /// rebuild so the load happens once the new view is in the hierarchy.
    func reattachLoad() {
        guard let pendingURL else { return }
        self.pendingURL = nil
        let delay = reattachDelay; reattachDelay = 0
        // Defer at least to the next runloop turn: a web view loaded synchronously
        // right after being attached doesn't render (its content process isn't mounted
        // yet). Recovery passes a larger delay to also drop the bad pooled connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.load(pendingURL) }
    }

    /// After each load, whether the page came out garbled (mojibake or a raw HTTP
    /// response shown as text). Auto-recovers up to `maxRecoverAttempts` times; if it's
    /// still bad we stop guessing and show a retry overlay instead of leaving garbage.
    func handleLoaded(garbled: Bool) {
        guard garbled else { recoverAttempts = 0; loadError = nil; return }
        guard recoverAttempts < Self.maxRecoverAttempts else {
            loadError = "페이지가 깨져서 표시됐어요. 다시 시도해 주세요."
            return
        }
        recoverAttempts += 1
        recover()
    }

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
