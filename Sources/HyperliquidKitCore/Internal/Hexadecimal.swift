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
