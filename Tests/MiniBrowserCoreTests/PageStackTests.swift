// Tests/MiniBrowserCoreTests/PageStackTests.swift
import XCTest
@testable import MiniBrowserCore

final class PageStackTests: XCTestCase {
    /// Test element: a page that is either alive or demoted to a name-only shell.
    private enum P: Equatable {
        case live(String)
        case dead(String)
        var isLive: Bool { if case .live = self { return true }; return false }
        var name: String { switch self { case .live(let n), .dead(let n): return n } }
    }

    private func makeStack(limit: Int = 5) -> PageStack<P> {
        PageStack(liveLimit: limit, isLive: { $0.isLive }, demote: { .dead($0.name) })
    }

    func testPushThenBackReturnsPushedPage() {
        var s = makeStack()
        s.push(current: .live("A"))
        XCTAssertTrue(s.canGoBack)
        XCTAssertEqual(s.goBack(current: .live("B")), .live("A"))
        XCTAssertTrue(s.canGoForward)          // B moved to forward
        XCTAssertFalse(s.canGoBack)
    }

    func testBackForwardRoundTripPreservesOrder() {
        var s = makeStack()
        s.push(current: .live("A"))
        s.push(current: .live("B"))                                  // back=[A,B]
        XCTAssertEqual(s.goBack(current: .live("C")), .live("B"))    // forward=[C]
        XCTAssertEqual(s.goBack(current: .live("B")), .live("A"))    // forward=[C,B]
        XCTAssertNil(s.goBack(current: .live("A")))
        XCTAssertEqual(s.goForward(current: .live("A")), .live("B"))
        XCTAssertEqual(s.goForward(current: .live("B")), .live("C"))
        XCTAssertNil(s.goForward(current: .live("C")))
        XCTAssertEqual(s.back, [.live("A"), .live("B")])
    }

    func testGoBackOnEmptyLeavesForwardUntouched() {
        var s = makeStack()
        s.push(current: .live("A"))
        _ = s.goBack(current: .live("B"))                            // forward=[B]
        XCTAssertNil(s.goBack(current: .live("A")))
        XCTAssertEqual(s.forward, [.live("B")])
    }

    func testPushClearsForwardAndReturnsDropped() {
        var s = makeStack()
        s.push(current: .live("A"))
        _ = s.goBack(current: .live("B"))                            // forward=[B]
        let dropped = s.push(current: .live("A"))                    // new navigation from A
        XCTAssertEqual(dropped, [.live("B")])
        XCTAssertFalse(s.canGoForward)
        XCTAssertEqual(s.back, [.live("A")])
    }

    func testLiveLimitDemotesFarthestOnBackStack() {
        var s = makeStack(limit: 2)
        s.push(current: .live("A"))
        s.push(current: .live("B"))
        s.push(current: .live("C"))                                  // 3 live > 2
        XCTAssertEqual(s.back, [.dead("A"), .live("B"), .live("C")])
        s.push(current: .live("D"))
        XCTAssertEqual(s.back, [.dead("A"), .dead("B"), .live("C"), .live("D")])
    }

    func testLiveLimitDemotesFarthestOnForwardStack() {
        var s = makeStack(limit: 1)
        s.push(current: .live("A"))
        s.push(current: .live("B"))                                  // back=[dead A, live B]
        XCTAssertEqual(s.goBack(current: .live("C")), .live("B"))    // forward=[C]
        XCTAssertEqual(s.goBack(current: .live("D")), .dead("A"))    // forward=[C,D] -> demote C
        XCTAssertEqual(s.forward, [.dead("C"), .live("D")])
        XCTAssertFalse(s.canGoBack)
    }

    func testDemoteAllWhereMatches() {
        var s = makeStack()
        s.push(current: .live("A"))
        s.push(current: .live("B"))
        _ = s.goBack(current: .live("C"))                            // back=[A], forward=[C]
        s.demoteAll { $0.name == "A" || $0.name == "C" }
        XCTAssertEqual(s.back, [.dead("A")])
        XCTAssertEqual(s.forward, [.dead("C")])
    }

    func testCanGoFlagsStartFalse() {
        let s = makeStack()
        XCTAssertFalse(s.canGoBack)
        XCTAssertFalse(s.canGoForward)
    }

    func testTopsPeekWithoutMutating() {
        var s = makeStack()
        XCTAssertNil(s.backTop)
        XCTAssertNil(s.forwardTop)
        s.push(current: .live("A"))
        s.push(current: .live("B"))
        XCTAssertEqual(s.backTop, .live("B"))            // what goBack() would reveal
        XCTAssertEqual(s.back, [.live("A"), .live("B")]) // unchanged by peeking
        _ = s.goBack(current: .live("C"))
        XCTAssertEqual(s.forwardTop, .live("C"))         // what goForward() would reveal
        XCTAssertEqual(s.backTop, .live("A"))
    }
}
