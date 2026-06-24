import XCTest
@testable import MiniBrowserCore

final class AdBlockRulesTests: XCTestCase {
    private func parsed() throws -> [[String: Any]] {
        let data = Data(AdBlockRules.json.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    func testIsValidNonEmptyRuleList() throws {
        let rules = try parsed()
        XCTAssertGreaterThan(rules.count, 10)
        for rule in rules {
            XCTAssertNotNil(rule["trigger"], "every rule needs a trigger")
            XCTAssertNotNil(rule["action"], "every rule needs an action")
        }
    }

    func testHasNetworkBlockRules() throws {
        let rules = try parsed()
        let blocks = rules.filter { ($0["action"] as? [String: Any])?["type"] as? String == "block" }
        XCTAssertGreaterThan(blocks.count, 5)
    }

    func testHasACosmeticHideRule() throws {
        let rules = try parsed()
        let css = rules.first { ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none" }
        let selector = (css?["action"] as? [String: Any])?["selector"] as? String
        XCTAssertNotNil(selector, "expected a css-display-none rule with a selector")
        XCTAssertTrue(selector?.contains("adsbygoogle") == true)
    }
}
