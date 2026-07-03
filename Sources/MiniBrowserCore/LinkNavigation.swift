// Sources/MiniBrowserCore/LinkNavigation.swift
import Foundation

/// Classifies a clicked link: should it be *stacked* (loaded in a fresh web view,
/// keeping the current page alive for instant back) or left to the current web
/// view (same-document fragment jumps, non-web schemes)?
public enum LinkNavigation {
    public static func shouldStack(url: URL, currentURL: URL?) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false   // javascript:, mailto:, … — let WebKit handle in place
        }
        // A fragment jump within the same document must stay in-page (no load at all).
        if url.fragment != nil, let currentURL,
           strippingFragment(url) == strippingFragment(currentURL) {
            return false
        }
        return true
    }

    private static func strippingFragment(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url
    }
}
