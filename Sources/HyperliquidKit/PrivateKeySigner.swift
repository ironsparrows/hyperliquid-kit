public import Foundation
public import HyperliquidKitCore
import P256K

extension Hyperliquid {
    /// Signs with a secp256k1 private key held in memory: an API wallet's key, or the account's own.
    ///
    /// Load the key from the Keychain or the environment and pass it in; never write it in source
    /// code. ``description``, `String(reflecting:)` and `dump(_:)` show only ``address``, never the key.
    ///
    /// Signatures are deterministic (RFC 6979): the same request and key always give the same signature.
    public struct PrivateKeySigner: Signer, CustomStringConvertible, CustomReflectable {
        public let address: Address
        private let key: Data

        /// Creates a signer from the key's 32 bytes.
        ///
        /// - Throws: ``ClientError`` with reason ``ClientError/Reason/invalidPrivateKey`` when the bytes
        ///   aren't a valid secp256k1 private key. The error doesn't contain the key.
        public init(privateKey: some ContiguousBytes) throws {
            let key = privateKey.withUnsafeBytes { Data($0) }
            guard key.count == 32, let signingKey = try? Self.signingKey(key) else {
                throw ClientError(.invalidPrivateKey, message: "Expected a valid 32-byte secp256k1 key")
            }
            self.key = key
            let publicKey = Array(signingKey.publicKey.dataRepresentation.dropFirst())
            address = try Address(hexadecimal(Keccak256.hash(publicKey).suffix(20)))
        }

        /// Creates a signer from the key as 64 hexadecimal digits, with or without `0x`.
        ///
        /// - Throws: ``ClientError`` with reason ``ClientError/Reason/invalidPrivateKey`` when the text
        ///   isn't a valid secp256k1 private key. The error doesn't contain the text.
        public init(hexKey: String) throws {
            let digits = hexKey.hasPrefix("0x") ? hexKey.dropFirst(2) : Substring(hexKey)
            guard digits.utf8.count == 64, let bytes = [UInt8](hexadecimal: digits) else {
                throw ClientError(.invalidPrivateKey, message: "Expected 64 hexadecimal digits")
            }
            try self.init(privateKey: bytes)
        }

        /// - Throws: ``ClientError`` with reason ``ClientError/Reason/invalidPrivateKey`` if the key
        ///   can't sign the request's digest. The error doesn't contain the key.
        public func sign(_ request: SigningRequest) async throws -> Signature {
            let compact: P256K.Recovery.ECDSACompactSignature
            do {
                compact = try Self.signingKey(key).signature(for: HashDigest(Array(request.digest))).compactRepresentation
            } catch {
                throw ClientError(.invalidPrivateKey, message: "The key couldn't sign a \(request.digest.count)-byte digest")
            }
            return try Signature(r: compact.signature.prefix(32), s: compact.signature.suffix(32), v: UInt8(compact.recoveryId) + 27)
        }

        public var description: String { "PrivateKeySigner(address: \(address))" }

        public var customMirror: Mirror {
            Mirror(self, children: ["address": address], displayStyle: .struct)
        }

        /// P256K's key type isn't `Sendable`, so the signer keeps the bytes and rebuilds it per signature.
        private static func signingKey(_ key: Data) throws -> P256K.Recovery.PrivateKey {
            try P256K.Recovery.PrivateKey(dataRepresentation: key, format: .uncompressed)
        }
    }
}
