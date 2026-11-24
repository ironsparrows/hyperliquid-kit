package import Foundation

/// A decimal Hyperliquid sends as a JSON string, such as `"60243.0"`, decoded without passing through
/// `Double`. A JSON number is accepted too.
package struct WireDecimal: Decodable, Sendable {
    package let value: Decimal

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Decimal.self) {
            value = number
            return
        }
        let text = try container.decode(String.self)
        guard let parsed = Decimal(wireString: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a decimal number: \(text)")
        }
        value = parsed
    }
}

extension Decimal {
    /// Parses a whole string as a decimal number, independent of the device's locale.
    ///
    /// `Decimal` keeps 38 significant digits and rounds beyond them; Hyperliquid's values have about 20.
    ///
    /// `Decimal(string:)` alone accepts a valid prefix (`"1.5x"` is 1.5, `"1,5"` is 1), so the string
    /// is checked first.
    init?(wireString text: String) {
        guard Self.isDecimalNumber(text.utf8),
            let value = Decimal(string: text, locale: Self.wireLocale),
            !value.isNaN
        else { return nil }
        self = value
    }

    /// The decimal as Hyperliquid expects it in an action: no exponent, no trailing zeros and no
    /// negative zero, so `100.0` is `"100"` and `1e-7` is `"0.0000001"`.
    ///
    /// Signatures cover this text, so a trailing zero would change what is signed.
    package var wireString: String { description }

    private static let wireLocale = Locale(identifier: "en_US_POSIX")

    /// Whether the bytes are `[+-]digits[.digits][(e|E)[+-]digits]`, with digits on at least one side
    /// of the point.
    private static func isDecimalNumber(_ bytes: String.UTF8View) -> Bool {
        var index = bytes.startIndex
        func skip(_ accepted: (UInt8) -> Bool) -> Int {
            var count = 0
            while index != bytes.endIndex, accepted(bytes[index]) {
                index = bytes.index(after: index)
                count += 1
            }
            return count
        }
        let isDigit: (UInt8) -> Bool = { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
        let isSign: (UInt8) -> Bool = { $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "-") }

        if index != bytes.endIndex, isSign(bytes[index]) { index = bytes.index(after: index) }
        var digits = skip(isDigit)
        if index != bytes.endIndex, bytes[index] == UInt8(ascii: ".") {
            index = bytes.index(after: index)
            digits += skip(isDigit)
        }
        guard digits > 0 else { return false }
        if index != bytes.endIndex, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index = bytes.index(after: index)
            if index != bytes.endIndex, isSign(bytes[index]) { index = bytes.index(after: index) }
            guard skip(isDigit) > 0 else { return false }
        }
        return index == bytes.endIndex
    }
}
