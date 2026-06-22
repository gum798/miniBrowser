import XCTest
@testable import MiniBrowserCore

final class TabsStateTests: XCTestCase {
    func testAddMakesActive() {
        var s = TabsState()
        let a = UUID()
        s.add(a)
        XCTAssertEqual(s.tabIDs, [a])
        XCTAssertEqual(s.activeID, a)
    }

    func testClosingActiveSelectsNextNeighbor() {
        var s = TabsState()
        let a = UUID(), b = UUID(), c = UUID()
        s.add(a); s.add(b); s.add(c)   // active == c
        s.select(b)                    // active == b
        s.close(b)
        XCTAssertEqual(s.tabIDs, [a, c])
        XCTAssertEqual(s.activeID, c)  // next neighbor
    }

    func testClosingLastActiveSelectsPrevious() {
        var s = TabsState()
        let a = UUID(), b = UUID()
        s.add(a); s.add(b)             // active == b (last)
        s.close(b)
        XCTAssertEqual(s.tabIDs, [a])
        XCTAssertEqual(s.activeID, a)
    }

    func testClosingOnlyTabClearsActive() {
        var s = TabsState()
        let a = UUID()
        s.add(a)
        s.close(a)
        XCTAssertTrue(s.tabIDs.isEmpty)
        XCTAssertNil(s.activeID)
    }

    func testClosingInactiveKeepsActive() {
        var s = TabsState()
        let a = UUID(), b = UUID()
        s.add(a); s.add(b)             // active == b
        s.close(a)
        XCTAssertEqual(s.activeID, b)
        XCTAssertEqual(s.tabIDs, [b])
    }

    func testMoveReorders() {
        var s = TabsState()
        let a = UUID(), b = UUID(), c = UUID()
        s.add(a); s.add(b); s.add(c)
        s.move(from: 0, to: 2)
        XCTAssertEqual(s.tabIDs, [b, c, a])
    }
}
