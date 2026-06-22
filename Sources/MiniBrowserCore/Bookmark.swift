import Foundation

public struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var url: URL
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, url: URL, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}
