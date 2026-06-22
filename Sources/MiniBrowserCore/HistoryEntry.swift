import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public var title: String
    public var lastVisited: Date
    public var visitCount: Int

    public init(url: URL, title: String, lastVisited: Date, visitCount: Int) {
        self.url = url
        self.title = title
        self.lastVisited = lastVisited
        self.visitCount = visitCount
    }
}
