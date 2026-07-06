import XCTest
@testable import MiniBrowserCore

final class SettingsStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDefaultsMatchCurrentLaunchBehavior() {
        let s = Settings()
        XCTAssertFalse(s.inverted)
        XCTAssertTrue(s.adBlockEnabled)
        XCTAssertTrue(s.bossModeEnabled)
    }

    func testRoundTrip() {
        let dir = tempDir()
        let s = Settings(inverted: true, adBlockEnabled: false, bossModeEnabled: false)
        SettingsStore(directory: dir).save(s)
        XCTAssertEqual(SettingsStore(directory: dir).load(), s)
    }

    func testLoadMissingReturnsDefaults() {
        XCTAssertEqual(SettingsStore(directory: tempDir()).load(), Settings())
    }

    func testCorruptFileReturnsDefaults() throws {
        let dir = tempDir()
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("settings.json"))
        XCTAssertEqual(SettingsStore(directory: dir).load(), Settings())
    }

    func testOlderFileWithMissingFieldsGetsDefaults() throws {
        let dir = tempDir()
        try Data(#"{"inverted":true}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        let s = SettingsStore(directory: dir).load()
        XCTAssertTrue(s.inverted)                 // present field honored
        XCTAssertTrue(s.adBlockEnabled)           // missing fields -> defaults
        XCTAssertTrue(s.bossModeEnabled)
    }

    func testUnknownFieldsIgnored() throws {
        let dir = tempDir()
        try Data(#"{"inverted":true,"futureSetting":123}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        XCTAssertTrue(SettingsStore(directory: dir).load().inverted)
    }

    func testFileExists() {
        let dir = tempDir()
        let store = SettingsStore(directory: dir)
        XCTAssertFalse(store.fileExists)
        store.save(Settings())
        XCTAssertTrue(store.fileExists)
    }
}
