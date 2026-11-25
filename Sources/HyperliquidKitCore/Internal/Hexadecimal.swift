/// Why `text` isn't `0x` and `digitCount` hexadecimal digits. It gives only the length, never the text,
/// which could be a private key pasted by mistake.
func hexadecimalExpectation(digitCount: Int, for text: String) -> String {
    "Expected 0x and \(digitCount) hexadecimal digits, got \(text.count) characters"
}

/// Whether `text` is `0x` followed by exactly `digitCount` hexadecimal digits, in either case.
func isPrefixedHexadecimal(_ text: String, digitCount: Int) -> Bool {
    let bytes = text.utf8
    guard bytes.count == 2 + digitCount, bytes.starts(with: "0x".utf8) else { return false }
    return bytes.dropFirst(2).allSatisfy { byte in
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "f"),
            UInt8(ascii: "A")...UInt8(ascii: "F"):
            true
        default:
            false
        }
    }
}

extension [UInt8] {
    /// The bytes `digits` spells, two hexadecimal digits per byte, or `nil` when it holds anything else.
    package init?(hexadecimal digits: some StringProtocol) {
        let characters = Array(digits.utf8)
        guard characters.count.isMultiple(of: 2) else { return nil }
        self.init()
        reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let high = nibble(characters[index]), let low = nibble(characters[index + 1]) else { return nil }
            append(high << 4 | low)
        }
    }
}

/// `0x` and the bytes as lower-case hexadecimal digits, two per byte.
package func hexadecimal(_ bytes: some Sequence<UInt8>) -> String {
    "0x"
        + bytes.map { byte in
            let digits = String(byte, radix: 16)
            return byte < 0x10 ? "0" + digits : digits
        }.joined()
}

private func nibble(_ character: UInt8) -> UInt8? {
    switch character {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
    default: nil
    }
}
