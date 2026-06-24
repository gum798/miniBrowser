import XCTest
@testable import MiniBrowserCore

final class HiddenElementsStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAddAndQueryByHost() {
        let store = HiddenElementsStore(directory: tempDir())
        store.add("#ad", host: "a.com")
        store.add(".banner", host: "a.com")
        XCTAssertEqual(store.selectors(host: "a.com"), ["#ad", ".banner"])
        XCTAssertEqual(store.selectors(host: "b.com"), [])
    }

    func testAddIsDeduplicated() {
        let store = HiddenElementsStore(directory: tempDir())
        store.add("#ad", host: "a.com")
        store.add("#ad", host: "a.com")
        XCTAssertEqual(store.selectors(host: "a.com"), ["#ad"])
    }

    func testResetClearsOnlyThatHost() {
        let store = HiddenElementsStore(directory: tempDir())
        store.add("#ad", host: "a.com")
        store.add("#x", host: "b.com")
        store.reset(host: "a.com")
        XCTAssertEqual(store.selectors(host: "a.com"), [])
        XCTAssertEqual(store.selectors(host: "b.com"), ["#x"])
    }

    func testPersistsAcrossInstances() {
        let dir = tempDir()
        let s1 = HiddenElementsStore(directory: dir)
        s1.add("#ad", host: "a.com")
        let s2 = HiddenElementsStore(directory: dir)
        XCTAssertEqual(s2.selectors(host: "a.com"), ["#ad"])
    }
}
