import Foundation

/// Case-insensitive substring matching for filtering bookmarks/history by a
/// typed query. An empty/whitespace query matches everything.
public enum TextSearch {
    public static func matches(_ query: String, anyOf fields: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return fields.contains { $0.lowercased().contains(q) }
    }
}
