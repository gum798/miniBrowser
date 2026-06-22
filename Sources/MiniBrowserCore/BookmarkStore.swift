import Foundation

public final class BookmarkStore {
    private let fileURL: URL
    private var items: [Bookmark]

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("bookmarks.json")
        self.items = Self.load(from: fileURL)
    }

    public func all() -> [Bookmark] { items }

    public func add(_ bookmark: Bookmark) {
        items.append(bookmark)
        persist()
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func move(from: Int, to: Int) {
        guard items.indices.contains(from), to >= 0, to <= items.count else { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(to, items.count))
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [Bookmark] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Bookmark].self, from: data)) ?? []
    }
}
