// Tests/MiniBrowserCoreTests/LinkNavigationTests.swift
import XCTest
@testable import MiniBrowserCore

final class LinkNavigationTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testDifferentPageStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/post/2"),
                                                 currentURL: url("https://a.com/list")))
    }

    func testQueryChangeStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/list?page=2"),
                                                 currentURL: url("https://a.com/list")))
    }

    func testIdenticalURLWithoutFragmentStacks() {
        // Re-clicking a link to the current page reloads it as a new entry, like a browser.
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/list"),
                                                 currentURL: url("https://a.com/list")))
    }

    func testFragmentJumpSameDocumentDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("https://a.com/post#comments"),
                                                  currentURL: url("https://a.com/post")))
    }

    func testFragmentToFragmentSameDocumentDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("https://a.com/post#b"),
                                                  currentURL: url("https://a.com/post#a")))
    }

    func testFragmentOnDifferentPageStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/other#c"),
                                                 currentURL: url("https://a.com/post")))
    }

    func testFragmentWithNilCurrentStacks() {
        XCTAssertTrue(LinkNavigation.shouldStack(url: url("https://a.com/post#c"), currentURL: nil))
    }

    func testJavascriptSchemeDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("javascript:void(0)"),
                                                  currentURL: url("https://a.com")))
    }

    func testMailtoDoesNotStack() {
        XCTAssertFalse(LinkNavigation.shouldStack(url: url("mailto:x@y.com"),
                                                  currentURL: url("https://a.com")))
    }
}
