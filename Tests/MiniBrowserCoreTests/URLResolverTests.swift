import XCTest
@testable import MiniBrowserCore

final class URLResolverTests: XCTestCase {
    func testEmptyReturnsNil() {
        XCTAssertNil(URLResolver.resolve("   "))
        XCTAssertNil(URLResolver.resolve(""))
    }

    func testExplicitSchemePassThrough() {
        XCTAssertEqual(URLResolver.resolve("https://a.com/x")?.absoluteString, "https://a.com/x")
        XCTAssertEqual(URLResolver.resolve("http://a.com")?.absoluteString, "http://a.com")
    }

    func testBareDomainGetsHttps() {
        XCTAssertEqual(URLResolver.resolve("example.com")?.absoluteString, "https://example.com")
    }

    func testLocalhostWithPort() {
        XCTAssertEqual(URLResolver.resolve("localhost:8080")?.absoluteString, "https://localhost:8080")
    }

    func testSingleWordBecomesSearch() {
        let url = URLResolver.resolve("swift")
        XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=swift")
    }

    func testPhraseBecomesEncodedSearch() {
        let url = URLResolver.resolve("hello world")
        XCTAssertEqual(url?.absoluteString, "https://www.google.com/search?q=hello%20world")
    }
}
