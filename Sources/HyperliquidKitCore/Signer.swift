public import Foundation

extension Hyperliquid {
    /// Signs actions for an account: with the account's own key, or with an API wallet's.
    ///
    /// ``PrivateKeySigner`` signs with a key in memory. Conform your own type to sign elsewhere, such
    /// as in a hardware wallet or a remote signing service.
    public protocol Signer: Sendable {
        /// The address of the key that signs. Hyperliquid recovers it from each signature.
        var address: Address { get }

        /// Signs an EIP-712 request: ``SigningRequest/digest`` is the hash to sign, and
        /// ``SigningRequest/typedData`` is the same request as EIP-712 JSON. The signature's `v` is the
        /// recovery ID plus 27, as Ethereum wallets return it.
        func sign(_ request: SigningRequest) async throws -> Signature
    }

    /// An EIP-712 message for a ``Signer`` to sign. Only the client creates requests.
    public struct SigningRequest: Hashable, Sendable {
        /// The 32-byte EIP-712 hash to sign.
        public let digest: Data
        /// The request as EIP-712 typed data in JSON, the form `eth_signTypedData_v4` takes.
        ///
        /// Published signing vectors verify ``digest``; this JSON hasn't yet been signed by a wallet
        /// and compared with it.
        public let typedData: String

        package init(digest: Data, typedData: String) {
            self.digest = digest
            self.typedData = typedData
        }
    }
}
