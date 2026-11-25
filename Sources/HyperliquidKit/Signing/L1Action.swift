import HyperliquidKitCore

/// An action an API wallet may sign, such as placing or canceling orders, with what its signature
/// covers besides the action itself.
struct L1Action {
    let action: ActionValue
    /// Milliseconds since 1970, unique per signer.
    let nonce: UInt64
    /// The sub-account or vault the action trades for.
    let vault: Hyperliquid.Address?
    /// Milliseconds since 1970 after which Hyperliquid rejects the action.
    let expiresAfter: UInt64?

    /// `keccak256(msgpack(action) ‖ nonce ‖ vault ‖ expiresAfter)`, integers big-endian. The vault is
    /// `0x00`, or `0x01` and its 20 bytes; `expiresAfter` is `0x00` and its 8 bytes, or nothing.
    var connectionID: [UInt8] {
        var bytes = action.messagePack + nonce.bigEndianBytes
        if let vault {
            bytes += [0x01] + vault.bytes
        } else {
            bytes.append(0x00)
        }
        if let expiresAfter {
            bytes += [0x00] + expiresAfter.bigEndianBytes
        }
        return Keccak256.hash(bytes)
    }

    /// The request the signer signs: an `Agent` whose source names the network, carrying
    /// ``connectionID``, in the `Exchange` domain on chain 1337.
    func signingRequest(on network: Hyperliquid.Network) -> Hyperliquid.SigningRequest {
        TypedData(
            domainName: "Exchange",
            chainID: 1337,
            primaryType: "Agent",
            fields: [
                .init(name: "source", value: .string(network.signatureSource)),
                .init(name: "connectionId", value: .bytes32(connectionID)),
            ]
        ).signingRequest
    }
}
