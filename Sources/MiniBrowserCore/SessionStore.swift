import Foundation

/// A single restored tab: its URL (nil = start page) plus its zoom and
/// color-inversion state.
public struct TabSnapshot: Codable, Equatable, Sendable {
    public var url: URL?
    public var zoom: Double
    public var inverted: Bool
    public init(url: URL?, zoom: Double, inverted: Bool) {
        self.url = url
        self.zoom = zoom
        self.inverted = inverted
    }
}

/// The whole window's restorable state: the open tabs and which one is active.
public struct Session: Codable, Equatable, Sendable {
    public var tabs: [TabSnapshot]
    public var activeIndex: Int?
    public init(tabs: [TabSnapshot], activeIndex: Int?) {
        self.tabs = tabs
        self.activeIndex = activeIndex
    }
}

/// Persists the open-tabs session to `session.json` so it survives restarts.
public final class SessionStore {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("session.json")
    }

    public func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
