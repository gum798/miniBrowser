// Sources/MiniBrowserApp/StackedPage.swift
import WebKit

/// One entry in a tab's page stack: a page kept fully alive (web view retained,
/// DOM/scroll intact) or, once evicted by the live cap, a URL-only placeholder
/// that reloads when the user navigates back to it.
struct StackedPage {
    /// nil = placeholder (page must reload when shown again).
    var webView: WKWebView?
    let url: URL?
    let title: String

    var isLive: Bool { webView != nil }
    func demoted() -> StackedPage { StackedPage(webView: nil, url: url, title: title) }
}
