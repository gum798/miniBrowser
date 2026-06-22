import Foundation

public enum URLResolver {
    public static func resolve(_ input: String, searchEngine: SearchEngine = .google) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let scheme = URL(string: trimmed)?.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return URL(string: trimmed)
        }

        if looksLikeHost(trimmed) {
            return URL(string: "https://\(trimmed)")
        }

        return searchEngine.searchURL(query: trimmed)
    }

    private static func looksLikeHost(_ s: String) -> Bool {
        guard !s.contains(" ") else { return false }
        let hostPart = s.split(separator: "/", maxSplits: 1).first.map(String.init) ?? s
        let bare = hostPart.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostPart
        if bare == "localhost" { return true }
        guard bare.contains(".") else { return false }
        return !bare.hasPrefix(".") && !bare.hasSuffix(".")
    }
}
