import Foundation
import WebKit
import AppKit
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

    private var kvo: [NSKeyValueObservation] = []
    private lazy var mouseSwipe = MouseSwipeNavigator(tab: self)

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = MobileUserAgent.iPhoneSafari   // G3: before any load
        webView.allowsBackForwardNavigationGestures = true       // two-finger swipe = back/forward
        observe()
        mouseSwipe.install(on: webView)                          // mouse edge-drag = back/forward
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

    deinit { kvo.forEach { $0.invalidate() } }   // G4: prevent crashes/leaks
}

/// Mobile-style edge swipe with the mouse: a horizontal left-button drag that
/// starts within the left third of the web view (≥100pt) and moves right goes
/// back; starting in the right third and moving left goes forward. Only edge
/// starts engage, so in-page horizontal gestures (carousels, sliders, maps,
/// text selection) in the middle are untouched.
@MainActor
private final class MouseSwipeNavigator: NSObject, NSGestureRecognizerDelegate {
    weak var tab: Tab?
    init(tab: Tab) { self.tab = tab }

    func install(on webView: WKWebView) {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        pan.delegate = self
        pan.delaysPrimaryMouseButtonEvents = false   // keep clicks/links snappy
        webView.addGestureRecognizer(pan)
    }

    private func edgeWidth(_ viewWidth: CGFloat) -> CGFloat { max(100, viewWidth / 3) }

    @objc func handle(_ gr: NSPanGestureRecognizer) {
        guard gr.state == .ended, let view = gr.view else { return }
        let t = gr.translation(in: view)
        guard abs(t.x) > abs(t.y) else { return }           // horizontal-dominant
        let startX = gr.location(in: view).x - t.x
        let w = view.bounds.width, edge = edgeWidth(w), threshold: CGFloat = 60
        if startX <= edge, t.x > threshold, tab?.canGoBack == true {
            tab?.goBack()
        } else if startX >= w - edge, t.x < -threshold, tab?.canGoForward == true {
            tab?.goForward()
        }
    }

    // WKWebView has its own recognizers; allow ours to engage alongside them.
    func gestureRecognizer(_ g: NSGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool { true }

    // Called at mouse-down (before movement), so only the start position is known
    // here — gate on edge start; direction/threshold are checked on .ended.
    func gestureRecognizerShouldBegin(_ gr: NSGestureRecognizer) -> Bool {
        guard let pan = gr as? NSPanGestureRecognizer, let view = gr.view else { return false }
        let startX = pan.location(in: view).x - pan.translation(in: view).x
        let w = view.bounds.width, edge = edgeWidth(w)
        return startX <= edge || startX >= w - edge
    }
}
