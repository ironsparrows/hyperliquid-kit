import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Address")
    struct AddressTests {
        @Test func `an address is stored lower-cased so two spellings are equal`() throws {
            let text = "0x8C967E73E6B15087C42A10D344CFF4C96D877F1D"
            let checksummed = try Hyperliquid.Address(text)
            let literal: Hyperliquid.Address = "0x8c967e73e6b15087c42a10d344cff4c96d877f1d"
            #expect(checksummed == literal)
            #expect("\(checksummed)" == "0x8c967e73e6b15087c42a10d344cff4c96d877f1d")
        }

        @Test(arguments: [
            "",
            "0x",
            "8c967e73e6b15087c42a10d344cff4c96d877f1d",
            "0X8c967e73e6b15087c42a10d344cff4c96d877f1d",
            "0x8c967e73e6b15087c42a10d344cff4c96d877f1",
            "0x8c967e73e6b15087c42a10d344cff4c96d877f1d0",
            "0x8c967e73e6b15087c42a10d344cff4c96d877f1g",
            " 0x8c967e73e6b15087c42a10d344cff4c96d877f1d",
        ])
        func `a string that isn't 0x and 40 hexadecimal digits throws an invalid address error`(text: String) {
            #expect {
                try Hyperliquid.Address(text)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidAddress
            }
        }

        @Test func `the error for a malformed address doesn't repeat the text`() {
            let key = "0x" + String(repeating: "ab", count: 32)
            #expect {
                try Hyperliquid.Address(key)
            } throws: { error in
                !"\(error)".contains("abab") && !error.localizedDescription.contains("abab")
            }
        }

        @Test func `an address decodes lower-cased and encodes as a string`() throws {
            let json = #"["0x8C967E73E6B15087C42A10D344CFF4C96D877F1D"]"#
            let decoded = try JSONDecoder().decode([Hyperliquid.Address].self, from: Data(json.utf8))
            let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
            #expect(encoded == #"["0x8c967e73e6b15087c42a10d344cff4c96d877f1d"]"#)
        }

        @Test func `a malformed address fails to decode without repeating the text`() {
            let json = #"[""# + "0x" + String(repeating: "ab", count: 32) + #""]"#
            #expect {
                try JSONDecoder().decode([Hyperliquid.Address].self, from: Data(json.utf8))
            } throws: { error in
                error is DecodingError && !"\(error)".contains("abab")
            }
        }

        @Test func `a malformed address literal stops the program`() async {
            await #expect(processExitsWith: .failure) {
                _ = Hyperliquid.Address(stringLiteral: "0x1234")
            }
        }
    }
}
