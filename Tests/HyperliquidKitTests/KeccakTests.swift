import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Keccak-256")
    struct KeccakTests {
        // Ethereum's published answers, which SHA3-256 doesn't give.
        @Test(arguments: [
            ("", "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
            ("abc", "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
        ])
        func `a message hashes to Ethereum's Keccak-256`(message: String, expected: String) {
            #expect(hexadecimal(Keccak256.hash(Array(message.utf8))) == expected)
        }
    }
}
