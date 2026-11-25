import Foundation
import HyperliquidKitCore

/// Hands out each signer's action nonces: the current time in milliseconds, or one more than the
/// signer's last nonce when that is later.
///
/// Hyperliquid keeps each signer's 100 highest nonces and rejects a repeat, so one counter per signer
/// and network serves every client in the process.
actor NonceSource {
    static let shared = NonceSource()

    private struct Key: Hashable {
        let signer: Hyperliquid.Address
        let network: Hyperliquid.Network
    }

    private let now: @Sendable () -> UInt64
    private var last: [Key: UInt64] = [:]

    init(now: @escaping @Sendable () -> UInt64 = { UInt64(Date().timeIntervalSince1970 * 1000) }) {
        self.now = now
    }

    func next(for signer: Hyperliquid.Address, on network: Hyperliquid.Network) -> UInt64 {
        let key = Key(signer: signer, network: network)
        let nonce = last[key].map { max(now(), $0 + 1) } ?? now()
        last[key] = nonce
        return nonce
    }

    /// Records a nonce the app chose, such as one it spends, so the signer's next nonce is higher. A
    /// nonce more than a day ahead, which Hyperliquid rejects, isn't recorded, so it can't push later
    /// nonces out of the range Hyperliquid accepts.
    func record(_ nonce: UInt64, for signer: Hyperliquid.Address, on network: Hyperliquid.Network) -> UInt64 {
        guard nonce <= now() + 86_400_000 else { return nonce }
        let key = Key(signer: signer, network: network)
        last[key] = max(last[key] ?? 0, nonce)
        return nonce
    }
}
