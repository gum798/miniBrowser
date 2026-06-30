import XCTest
@testable import MiniBrowserCore

final class PageGarbleTests: XCTestCase {
    // MARK: mojibake (high replacement-char ratio)

    func testNormalKoreanPageIsNotGarbled() {
        XCTAssertFalse(PageGarble.isGarbled(
            replacementRatio: 0, hasReplacementChar: false,
            bodyPrefix: "오늘의 핫딜 모음 — 뽐뿌 인기 게시판"))
    }

    func testNormalEnglishPageIsNotGarbled() {
        XCTAssertFalse(PageGarble.isGarbled(
            replacementRatio: 0, hasReplacementChar: false,
            bodyPrefix: "Welcome to the front page. Today's top stories."))
    }

    func testHighReplacementRatioIsGarbled() {
        XCTAssertTrue(PageGarble.isGarbled(
            replacementRatio: 0.3, hasReplacementChar: true,
            bodyPrefix: "\u{FFFD}\u{FFFD}\u{FFFD} 뼁 \u{FFFD}"))
    }

    func testRatioJustAboveThresholdIsGarbled() {
        XCTAssertTrue(PageGarble.isGarbled(
            replacementRatio: 0.1001, hasReplacementChar: true, bodyPrefix: "x"))
    }

    func testRatioAtThresholdAloneIsNotGarbled() {
        // boundary: only strictly > 0.1 counts as mojibake
        XCTAssertFalse(PageGarble.isGarbled(
            replacementRatio: 0.1, hasReplacementChar: true,
            bodyPrefix: "안녕하세요 반갑습니다"))
    }

    // MARK: raw HTTP response (headers + gzip) rendered as text — connection desync

    func testRawHttpResponseShownAsTextIsGarbled() {
        // The exact failure: the body starts with response headers, then gzip bytes.
        let prefix = "Set-Cookie: m_gad_pos_600=29; path=/ Set-Cookie: " +
            "m_gad_pos_passback_600=1; path=/ Vary: Accept-Encoding " +
            "Content-Encoding: gzip Expires: Tue, 30 Jun 2026 01:39:12 GMT \u{FFFD}\u{FFFD}"
        XCTAssertTrue(PageGarble.isGarbled(
            replacementRatio: 0.04, hasReplacementChar: true, bodyPrefix: prefix))
    }

    func testRawHttpStatusLineIsGarbled() {
        XCTAssertTrue(PageGarble.isGarbled(
            replacementRatio: 0.02, hasReplacementChar: true,
            bodyPrefix: "HTTP/1.1 200 OK\nContent-Type: text/html"))
    }

    // MARK: false-positive guards — legit pages that mention HTTP headers

    func testArticleAboutHeadersIsNotGarbled() {
        // A real article that happens to start with header-looking text but has no
        // undecodable bytes must NOT be treated as garbage.
        XCTAssertFalse(PageGarble.isGarbled(
            replacementRatio: 0, hasReplacementChar: false,
            bodyPrefix: "Content-Encoding: gzip explained — how HTTP compression works"))
    }

    func testSetCookieTutorialWithoutReplacementCharIsNotGarbled() {
        XCTAssertFalse(PageGarble.isGarbled(
            replacementRatio: 0, hasReplacementChar: false,
            bodyPrefix: "Set-Cookie header tutorial: everything you need to know"))
    }

    func testEmptyPrefixIsNotGarbled() {
        XCTAssertFalse(PageGarble.isGarbled(
            replacementRatio: 0, hasReplacementChar: false, bodyPrefix: ""))
    }
}
