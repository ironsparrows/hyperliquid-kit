import CryptoSwift

// The only file that imports CryptoSwift: its top-level `Digest` and `Signature` would collide with
// CryptoKit's, which P256K re-exports.

/// Ethereum's Keccak-256: the original Keccak padding, not SHA3-256's.
enum Keccak256 {
    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        SHA3(variant: .keccak256).calculate(for: bytes)
    }
}
