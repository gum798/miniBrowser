import Foundation

public final class HistoryStore {
    private let fileURL: URL
    private var items: [HistoryEntry]

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("history.json")
        self.items = Self.load(from: fileURL)
    }

    public func record(url: URL, title: String, now: Date = Date()) {
        if let idx = items.firstIndex(where: { $0.url == url }) {
            items[idx].title = title
            items[idx].lastVisited = now
            items[idx].visitCount += 1
        } else {
            items.append(HistoryEntry(url: url, title: title, lastVisited: now, visitCount: 1))
        }
        persist()
    }

    public func recent(limit: Int) -> [HistoryEntry] {
        Array(items.sorted { $0.lastVisited > $1.lastVisited }.prefix(limit))
    }

    public func suggestions(for prefix: String, limit: Int) -> [HistoryEntry] {
        let needle = prefix.lowercased()
        guard !needle.isEmpty else { return [] }
        return items
            .filter {
                $0.url.absoluteString.lowercased().contains(needle)
                    || $0.title.lowercased().contains(needle)
            }
            .sorted { ($0.visitCount, $0.lastVisited) > ($1.visitCount, $1.lastVisited) }
            .prefix(limit)
            .map { $0 }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }
}
