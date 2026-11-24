public import Foundation

extension Hyperliquid {
    /// A recoverable secp256k1 ECDSA signature.
    public struct Signature: Hashable, Sendable {
        /// 32 bytes.
        public let r: Data
        /// 32 bytes.
        public let s: Data
        /// The recovery ID plus 27: 27 or 28.
        public let v: UInt8

        /// Creates a signature from its parts.
        ///
        /// - Throws: ``ClientError`` with reason ``ClientError/Reason/invalidSignature`` when `r` or `s`
        ///   isn't 32 bytes or `v` isn't 27 or 28.
        public init(r: some DataProtocol, s: some DataProtocol, v: UInt8) throws {
            guard r.count == 32, s.count == 32 else {
                throw ClientError(.invalidSignature, message: "Expected 32-byte r and s, got \(r.count) and \(s.count)")
            }
            guard v == 27 || v == 28 else {
                throw ClientError(.invalidSignature, message: "Expected v of 27 or 28, got \(v)")
            }
            self.r = Data(r)
            self.s = Data(s)
            self.v = v
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Signature {
    /// `r` as Hyperliquid's requests carry it: `0x` and hexadecimal digits without leading zeros, `0x0`
    /// for zero.
    package var wireR: String { Self.minimalHexadecimal(r) }

    /// `s`, written as ``wireR`` is.
    package var wireS: String { Self.minimalHexadecimal(s) }

    private static func minimalHexadecimal(_ bytes: Data) -> String {
        let digits = hexadecimal(bytes).dropFirst(2).drop { $0 == "0" }
        return "0x" + (digits.isEmpty ? "0" : digits)
    }
}
