import Foundation

/// A WebKit content-blocker rule list (the same JSON format Safari content
/// blockers use): block requests to common ad/tracker hosts, and hide the
/// usual ad containers with a cosmetic rule. Pure, so it's unit-tested.
public enum AdBlockRules {
    /// Hosts to block outright (matched as a regex against the request URL).
    private static let blockedHosts = [
        "doubleclick\\.net", "googlesyndication\\.com", "googleadservices\\.com",
        "google-analytics\\.com", "googletagmanager\\.com", "googletagservices\\.com",
        "adservice\\.google\\.", "2mdn\\.net", "amazon-adsystem\\.com", "adnxs\\.com",
        "criteo\\.com", "criteo\\.net", "taboola\\.com", "outbrain\\.com", "rubiconproject\\.com",
        "pubmatic\\.com", "openx\\.net", "scorecardresearch\\.com", "quantserve\\.com",
        "moatads\\.com", "adcolony\\.com", "applovin\\.com", "adsrvr\\.org",
        "casalemedia\\.com", "smartadserver\\.com", "teads\\.tv", "media\\.net",
        "mgid\\.com", "revcontent\\.com", "zedo\\.com", "hotjar\\.com",
        "connect\\.facebook\\.net", "sb\\.scorecardresearch\\.com", "adform\\.net",
    ]

    /// Elements to hide everywhere (cosmetic filtering).
    private static let hideSelector = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"div-gpt-ad\"]", "[id^=\"google_ads_\"]",
        "[id^=\"taboola\"]", "[class*=\"adsbygoogle\"]", "iframe[src*=\"googlesyndication.com\"]",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"amazon-adsystem.com\"]",
        ".advertisement", ".ad-slot", ".ad-banner", ".sponsored-post",
    ].joined(separator: ", ")

    public static var json: String {
        var rules: [[String: Any]] = blockedHosts.map { host in
            ["trigger": ["url-filter": host], "action": ["type": "block"]]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": hideSelector],
        ])
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
