import XCTest
@testable import MiniBrowserCore

final class TextSearchTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(TextSearch.matches("", anyOf: ["anything"]))
        XCTAssertTrue(TextSearch.matches("   ", anyOf: ["anything"]))
    }

    func testMatchesIsCaseInsensitive() {
        XCTAssertTrue(TextSearch.matches("PPOM", anyOf: ["https://m.ppomppu.co.kr"]))
        XCTAssertTrue(TextSearch.matches("챗봇", anyOf: ["경기지역화폐 챗봇 DEV"]))
    }

    func testMatchesAnyField() {
        // matches when ANY field contains the query (title OR url)
        XCTAssertTrue(TextSearch.matches("ppom", anyOf: ["Some Title", "https://m.ppomppu.co.kr"]))
        XCTAssertTrue(TextSearch.matches("title", anyOf: ["Some Title", "https://example.com"]))
    }

    func testNoMatchReturnsFalse() {
        XCTAssertFalse(TextSearch.matches("zzz", anyOf: ["abc", "https://def.com"]))
    }

    func testQueryIsTrimmedBeforeMatching() {
        XCTAssertTrue(TextSearch.matches("  ppom  ", anyOf: ["https://m.ppomppu.co.kr"]))
    }
}
