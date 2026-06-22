import XCTest
@testable import MiniBrowserCore

final class BookmarkStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAddAndAll() {
        let store = BookmarkStore(directory: tempDir())
        store.add(Bookmark(title: "Apple", url: URL(string: "https://apple.com")!))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.title, "Apple")
    }

    func testRemove() {
        let store = BookmarkStore(directory: tempDir())
        let b = Bookmark(title: "A", url: URL(string: "https://a.com")!)
        store.add(b)
        store.remove(id: b.id)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testPersistenceRoundTrip() {
        let dir = tempDir()
        let s1 = BookmarkStore(directory: dir)
        s1.add(Bookmark(title: "Z", url: URL(string: "https://z.com")!))
        let s2 = BookmarkStore(directory: dir)   // re-load from disk
        XCTAssertEqual(s2.all().count, 1)
        XCTAssertEqual(s2.all().first?.url.absoluteString, "https://z.com")
    }

    func testMoveReorders() {
        let store = BookmarkStore(directory: tempDir())
        store.add(Bookmark(title: "1", url: URL(string: "https://1.com")!))
        store.add(Bookmark(title: "2", url: URL(string: "https://2.com")!))
        store.move(from: 0, to: 1)
        XCTAssertEqual(store.all().map(\.title), ["2", "1"])
    }
}
