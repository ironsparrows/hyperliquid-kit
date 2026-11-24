import Foundation
import Testing
@testable import HyperliquidKitCore

extension HyperliquidKitCoreTests {
    @Suite("Decimal coding")
    struct DecimalCodingTests {
        // The first four are recorded: an open interest, a price, a size and a funding rate.
        @Test(arguments: [
            ("4742371168.9723863602", "4742371168.9723863602"),
            ("60243.0", "60243"),
            ("0.00021", "0.00021"),
            ("-0.0000125", "-0.0000125"),
            ("1e-7", "0.0000001"),
            ("1E+3", "1000"),
        ])
        func `a decimal string decodes exactly`(text: String, expected: String) throws {
            let json = #"[""# + text + #""]"#
            let decoded = try JSONDecoder().decode([WireDecimal].self, from: Data(json.utf8))
            #expect(decoded.first?.value.wireString == expected)
        }

        @Test func `a JSON number decodes too`() throws {
            let decoded = try JSONDecoder().decode([WireDecimal].self, from: Data("[0.1, 60243]".utf8))
            #expect(decoded.map(\.value) == [Decimal(string: "0.1")!, 60243])
        }

        @Test(arguments: ["", "1.5x", "1,5", ".", "-", "1e", "NaN", "0x10", " 1"])
        func `a string that isn't a whole decimal number fails to decode`(text: String) {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode([WireDecimal].self, from: Data((#"[""# + text + #""]"#).utf8))
            }
        }

        @Test(arguments: [
            ("100.0", "100"),
            ("1670.10", "1670.1"),
            ("1e-7", "0.0000001"),
            ("-0.0", "0"),
            ("-12.5000", "-12.5"),
            ("00012.30", "12.3"),
            ("0.000018", "0.000018"),
        ])
        func `a decimal is written without exponent, trailing zeros or negative zero`(text: String, expected: String) throws {
            let value = try #require(Decimal(wireString: text))
            #expect(value.wireString == expected)
        }
    }
}
