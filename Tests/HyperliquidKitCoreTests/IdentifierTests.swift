import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Identifiers")
    struct IdentifierTests {
        @Test func `order and TWAP IDs round-trip as JSON integers`() throws {
            let json = "[610655084237,18446744073709551615]"
            #expect(try roundTrip(Hyperliquid.OrderID.self, json) == json)
            #expect(try roundTrip(Hyperliquid.TwapID.self, json) == json)
            #expect("\(Hyperliquid.OrderID(rawValue: 610_655_084_237))" == "610655084237")
        }

        @Test func `a transaction hash round-trips unchanged`() throws {
            let json = #"["0x0000000000000000000000000000000000000000000000000000000000000000"]"#
            #expect(try roundTrip(Hyperliquid.TransactionHash.self, json) == json)
        }

        @Test func `a client order ID is stored lower-cased`() throws {
            let text = "0x1234567890ABCDEF1234567890ABCDEF"
            let id = try Hyperliquid.ClientOrderID(text)
            #expect("\(id)" == "0x1234567890abcdef1234567890abcdef")
            #expect(
                try roundTrip(Hyperliquid.ClientOrderID.self, #"["0x1234567890ABCDEF1234567890ABCDEF"]"#)
                    == #"["0x1234567890abcdef1234567890abcdef"]"#)
        }

        @Test(arguments: [
            "",
            "1234567890abcdef1234567890abcdef",
            "0x1234567890abcdef1234567890abcde",
            "0x1234567890abcdef1234567890abcdef0",
            "0x1234567890abcdef1234567890abcdeg",
        ])
        func `a string that isn't 0x and 32 hexadecimal digits throws an invalid client order ID error`(text: String) {
            #expect {
                try Hyperliquid.ClientOrderID(text)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidClientOrderID
            }
        }

        @Test func `a random client order ID is 0x and 32 hexadecimal digits and differs each time`() throws {
            let ids = (0..<100).map { _ in Hyperliquid.ClientOrderID.random() }
            for id in ids {
                #expect(try Hyperliquid.ClientOrderID("\(id)") == id)
            }
            #expect(Set(ids).count == ids.count)
        }

        private func roundTrip<Value: Codable>(_ type: Value.Type, _ json: String) throws -> String {
            let decoded = try JSONDecoder().decode([Value].self, from: Data(json.utf8))
            return String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        }
    }
}
