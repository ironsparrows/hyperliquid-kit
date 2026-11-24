import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Signature")
    struct SignatureTests {
        private let r = Data([0x00, 0x05] + Array(repeating: 0xab, count: 30))
        private let s = Data(repeating: 0x7f, count: 32)

        @Test func `r and s are sent as hexadecimal without leading zeros`() throws {
            let signature = try Hyperliquid.Signature(r: r, s: s, v: 27)
            #expect(signature.wireR == "0x5" + String(repeating: "ab", count: 30))
            #expect(signature.wireS == "0x" + String(repeating: "7f", count: 32))
        }

        @Test(arguments: [(31, 32, UInt8(27)), (32, 33, 27), (32, 32, 0), (32, 32, 1), (32, 32, 29)])
        func `a part of the wrong size or another v throws an invalid signature error`(rCount: Int, sCount: Int, v: UInt8) {
            #expect {
                try Hyperliquid.Signature(r: Data(count: rCount), s: Data(count: sCount), v: v)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidSignature
            }
        }
    }
}
