import XCTest
@testable import MiniBrowserCore

final class PageZoomTests: XCTestCase {
    func testStepsUpAndDown() {
        XCTAssertEqual(PageZoom.stepped(1.0, by: 1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(PageZoom.stepped(1.0, by: -1), 0.9, accuracy: 0.0001)
    }

    func testClampsToBounds() {
        XCTAssertEqual(PageZoom.stepped(0.5, by: -5), PageZoom.lower, accuracy: 0.0001)
        XCTAssertEqual(PageZoom.stepped(3.0, by: 10), PageZoom.upper, accuracy: 0.0001)
    }

    func testNoFloatingPointDrift() {
        // 1.0 + 3 * 0.1 should be exactly 1.3, not 1.3000000000000003
        XCTAssertEqual(PageZoom.stepped(1.0, by: 3), 1.3)
    }
}
