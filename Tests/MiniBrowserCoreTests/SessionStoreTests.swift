import XCTest
@testable import MiniBrowserCore

final class SessionStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRoundTrip() {
        let dir = tempDir()
        let session = Session(tabs: [
            TabSnapshot(url: URL(string: "https://a.com"), zoom: 1.2, inverted: true),
            TabSnapshot(url: nil, zoom: 1.0, inverted: false),
        ], activeIndex: 1)
        SessionStore(directory: dir).save(session)
        XCTAssertEqual(SessionStore(directory: dir).load(), session)
    }

    func testLoadMissingReturnsNil() {
        XCTAssertNil(SessionStore(directory: tempDir()).load())
    }

    func testEmptySessionRoundTrips() {
        let dir = tempDir()
        SessionStore(directory: dir).save(Session(tabs: [], activeIndex: nil))
        XCTAssertEqual(SessionStore(directory: dir).load(), Session(tabs: [], activeIndex: nil))
    }
}
