import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Private key signer")
    struct PrivateKeySignerTests {
        private let key = SigningVectors.pythonTestKey

        @Test func `the signer's address is derived from its key`() throws {
            let signer = try Hyperliquid.PrivateKeySigner(hexKey: key)
            #expect(signer.address == "0x14791697260e4c9a71f18484c9f997b308e59325")
        }

        @Test func `a key reads the same with or without 0x and as bytes`() throws {
            let withPrefix = try Hyperliquid.PrivateKeySigner(hexKey: key)
            let withoutPrefix = try Hyperliquid.PrivateKeySigner(hexKey: String(key.dropFirst(2)))
            let fromBytes = try Hyperliquid.PrivateKeySigner(privateKey: Data([UInt8](hexadecimal: key.dropFirst(2))!))
            #expect(withoutPrefix.address == withPrefix.address)
            #expect(fromBytes.address == withPrefix.address)
        }

        @Test func `printing or dumping the signer shows its address but never its key`() throws {
            let signer = try Hyperliquid.PrivateKeySigner(hexKey: key)
            var dumped = ""
            dump(signer, to: &dumped)
            for text in [signer.description, String(reflecting: signer), "\(signer)", dumped] {
                #expect(text.contains("0x14791697260e4c9a71f18484c9f997b308e59325"))
                #expect(!text.contains("0123456789012345"))
                #expect(!text.contains("key"))
            }
            #expect(Mirror(reflecting: signer).children.map(\.label) == ["address"])
        }

        @Test(arguments: [31, 33])
        func `bytes that aren't 32 long throw an invalid private key error`(count: Int) {
            #expect {
                try Hyperliquid.PrivateKeySigner(privateKey: Data(repeating: 1, count: count))
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidPrivateKey
            }
        }

        @Test func `a zero key as bytes throws an invalid private key error`() {
            #expect {
                try Hyperliquid.PrivateKeySigner(privateKey: Data(count: 32))
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidPrivateKey
            }
        }

        @Test(arguments: [
            "",
            "0x",
            "0x0123",
            "0x012345678901234567890123456789012345678901234567890123456789012g",
            "0x" + String(repeating: "0", count: 64),
            "0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
        ])
        func `text that isn't a valid secp256k1 key throws without repeating it`(text: String) {
            #expect {
                try Hyperliquid.PrivateKeySigner(hexKey: text)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidPrivateKey
                    && (text.count < 8 || !"\(error)".contains(text.dropFirst(2).prefix(8)))
            }
        }
    }
}
