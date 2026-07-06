import XCTest
@testable import MiniBrowserCore

final class EdgeTapTests: XCTestCase {
    func testStationaryTapForwards() {
        XCTAssertTrue(EdgeTap.shouldForwardClick(becameSwipe: false, movement: 0))
    }

    func testTinyJitterStillForwards() {
        XCTAssertTrue(EdgeTap.shouldForwardClick(becameSwipe: false, movement: 5.9))
    }

    func testMovementAtSlopForwards() {
        XCTAssertTrue(EdgeTap.shouldForwardClick(becameSwipe: false, movement: 6))
    }

    func testMovedBeyondSlopIsSwallowed() {
        // A failed swipe attempt (moved, but never horizontal enough) must not click.
        XCTAssertFalse(EdgeTap.shouldForwardClick(becameSwipe: false, movement: 6.1))
    }

    func testSwipeNeverForwards() {
        XCTAssertFalse(EdgeTap.shouldForwardClick(becameSwipe: true, movement: 0))
        XCTAssertFalse(EdgeTap.shouldForwardClick(becameSwipe: true, movement: 120))
    }

    func testCustomSlop() {
        XCTAssertTrue(EdgeTap.shouldForwardClick(becameSwipe: false, movement: 9, slop: 10))
        XCTAssertFalse(EdgeTap.shouldForwardClick(becameSwipe: false, movement: 11, slop: 10))
    }
}
