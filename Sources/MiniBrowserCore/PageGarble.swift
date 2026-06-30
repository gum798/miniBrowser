import Foundation

/// Detects when a finished page came out *garbled* and should be auto-recovered.
///
/// Two distinct WebKit failure modes are caught, both seen on long-lived web views:
///  - **mojibake** — a wrong text decoding (e.g. EUC-KR read as UTF-8) yields a high
///    fraction of U+FFFD replacement characters.
///  - **raw HTTP response shown as text** — a keep-alive connection desync makes the
///    body the literal HTTP response (status line / `Set-Cookie:` / `Content-Encoding:
///    gzip` headers, then the undecodable gzip bytes) instead of the rendered page.
public enum PageGarble {
    /// Header lines that should never begin a real rendered page's visible text. If a
    /// page's `innerText` starts with one of these, the HTTP response framing leaked
    /// into the document body.
    private static let headerPrefixes = [
        "http/1.", "set-cookie:", "content-encoding:", "content-type:",
        "content-length:", "vary:", "cache-control:", "pragma:", "expires:",
        "date:", "server:", "connection:",
    ]

    /// - Parameters:
    ///   - replacementRatio: fraction of U+FFFD characters across the body's `innerText`.
    ///   - hasReplacementChar: whether the body contains any U+FFFD at all.
    ///   - bodyPrefix: the leading characters of the body's `innerText`.
    public static func isGarbled(replacementRatio: Double,
                                 hasReplacementChar: Bool,
                                 bodyPrefix: String) -> Bool {
        // Mojibake: lots of replacement characters relative to the text length.
        if replacementRatio > 0.1 { return true }

        // Connection desync: the body *starts* with an HTTP header line. Require an
        // undecodable byte too, so a legit article that merely mentions a header name
        // (e.g. "Content-Encoding: gzip explained") is not flagged.
        let head = bodyPrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard headerPrefixes.contains(where: head.hasPrefix) else { return false }
        return hasReplacementChar
    }
}
