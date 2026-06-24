import XCTest
@testable import MiniBrowserCore

final class SafariBookmarksTests: XCTestCase {
    // Build plist Data mirroring Safari's Bookmarks.plist node shapes.
    private func plist(_ root: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }
    private func leaf(_ title: String?, _ url: String) -> [String: Any] {
        var d: [String: Any] = ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": url]
        if let title { d["URIDictionary"] = ["title": title] }
        return d
    }
    private func folder(_ title: String, _ children: [[String: Any]]) -> [String: Any] {
        ["WebBookmarkType": "WebBookmarkTypeList", "Title": title, "Children": children]
    }

    func testParsesLeavesIncludingNestedFolders() {
        let data = plist(folder("", [
            leaf("Apple", "https://apple.com"),
            folder("Dev", [leaf("Swift", "https://swift.org")]),
        ]))
        let result = SafariBookmarks.parse(data)
        XCTAssertEqual(result.map(\.title), ["Apple", "Swift"])
        XCTAssertEqual(result.map { $0.url.absoluteString }, ["https://apple.com", "https://swift.org"])
    }

    func testSkipsProxyNodes() {
        let proxy: [String: Any] = ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"]
        let data = plist(folder("", [leaf("A", "https://a.com"), proxy]))
        XCTAssertEqual(SafariBookmarks.parse(data).map(\.title), ["A"])
    }

    func testDeduplicatesByURLKeepingFirst() {
        let data = plist(folder("", [
            leaf("First", "https://dup.com"),
            leaf("Second", "https://dup.com"),
        ]))
        let result = SafariBookmarks.parse(data)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "First")
    }

    func testFallsBackToURLWhenTitleMissingOrEmpty() {
        let data = plist(folder("", [
            leaf(nil, "https://no-title.com"),
            leaf("", "https://empty-title.com"),
        ]))
        XCTAssertEqual(SafariBookmarks.parse(data).map(\.title),
                       ["https://no-title.com", "https://empty-title.com"])
    }

    func testReturnsEmptyForGarbage() {
        XCTAssertTrue(SafariBookmarks.parse(Data("not a plist".utf8)).isEmpty)
    }

    func testReadOkFromFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Bookmarks.plist")
        try plist(folder("", [leaf("Apple", "https://apple.com")])).write(to: file)
        guard case .ok(let items) = SafariBookmarks.read(from: file) else {
            return XCTFail("expected .ok")
        }
        XCTAssertEqual(items.map(\.title), ["Apple"])
    }

    func testReadUnavailableWhenMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/Bookmarks.plist")
        XCTAssertEqual(SafariBookmarks.read(from: missing), .unavailable)
    }
}
