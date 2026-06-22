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

    private var kvo: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = MobileUserAgent.iPhoneSafari   // G3: before any load
        observe()
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
