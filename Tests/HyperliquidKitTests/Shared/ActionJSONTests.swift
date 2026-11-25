import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Action JSON")
    struct ActionJSONTests {
        @Test func `an action is written as compact JSON with its keys in order`() {
            let value: ActionValue = [
                "action": ["type": "order", "orders": [["a": 4, "b": true, "p": "1670.1", "r": false]]],
                "nonce": 1_677_777_606_040, "vaultAddress": nil, "n": -7,
            ]
            #expect(
                value.json
                    == #"{"action":{"type":"order","orders":[{"a":4,"b":true,"p":"1670.1","r":false}]},"nonce":1677777606040,"vaultAddress":null,"n":-7}"#
            )
        }

        @Test func `strings are escaped so the JSON parses back to the same text`() throws {
            let text = "quote \" backslash \\ newline \n tab \t bell \u{7} é 🙂"
            let json = ActionValue.array([.string(text)]).json
            #expect(json == #"["quote \" backslash \\ newline \n tab \t bell \u0007 é 🙂"]"#)
            let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String]
            #expect(parsed == [text])
        }
    }
}
