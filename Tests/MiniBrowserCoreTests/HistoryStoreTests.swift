import XCTest
@testable import MiniBrowserCore

final class HistoryStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func u(_ s: String) -> URL { URL(string: s)! }

    func testRecordThenRecent() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://a.com"), title: "A", now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(store.recent(limit: 10).map(\.url), [u("https://a.com")])
    }

    func testDuplicateUrlDedupesAndCounts() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://a.com"), title: "A", now: Date(timeIntervalSince1970: 1))
        store.record(url: u("https://a.com"), title: "A2", now: Date(timeIntervalSince1970: 2))
        let all = store.recent(limit: 10)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.visitCount, 2)
        XCTAssertEqual(all.first?.title, "A2")            // latest title wins
        XCTAssertEqual(all.first?.lastVisited, Date(timeIntervalSince1970: 2))
    }

    func testRecentSortedByLastVisitedDescending() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://a.com"), title: "A", now: Date(timeIntervalSince1970: 1))
        store.record(url: u("https://b.com"), title: "B", now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(store.recent(limit: 10).map(\.url), [u("https://b.com"), u("https://a.com")])
    }

    func testSuggestionsMatchPrefixCaseInsensitively() {
        let store = HistoryStore(directory: tempDir())
        store.record(url: u("https://apple.com"), title: "Apple", now: Date(timeIntervalSince1970: 1))
        store.record(url: u("https://google.com"), title: "Google", now: Date(timeIntervalSince1970: 2))
        let s = store.suggestions(for: "App", limit: 10)
        XCTAssertEqual(s.map(\.url), [u("https://apple.com")])
    }

    func testPersistenceRoundTrip() {
        let dir = tempDir()
        let s1 = HistoryStore(directory: dir)
        s1.record(url: u("https://z.com"), title: "Z", now: Date(timeIntervalSince1970: 1))
        let s2 = HistoryStore(directory: dir)
        XCTAssertEqual(s2.recent(limit: 10).count, 1)
    }
}
