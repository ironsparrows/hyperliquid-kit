import Foundation
import HyperliquidKitCore

/// An account's TWAP orders, read from `/info`, and its TWAP actions, sent to `/exchange`.
struct TwapRequests: Hyperliquid.TwapAPI {
    let info: InfoClient
    let exchange: ExchangeClient
    let directory: AssetDirectory
    /// The account a read uses when it is given none.
    let account: Hyperliquid.Address?

    func sliceFills(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.TwapSliceFill] {
        try await info.send(.userTwapSliceFills(try resolveAccount(user, default: account)))
    }

    func history(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.TwapHistoryEntry] {
        try await info.send(.twapHistory(try resolveAccount(user, default: account)))
    }
}

// MARK: - Actions

extension TwapRequests {
    func place(_ twap: Hyperliquid.TwapRequest, expiresAfter: Date?) async throws -> Hyperliquid.TwapPlacementResult {
        _ = try exchange.requireSigner()
        let minutes = try wholeMinutes(twap.duration)
        let size = try wireNumber(twap.size, "size")
        let asset = try await directory.asset(for: twap.coin).id
        let action: ActionValue = [
            "type": "twapOrder",
            "twap": [
                "a": .unsigned(UInt64(asset)), "b": .bool(twap.side == .buy), "s": .string(size),
                "r": .bool(twap.reduceOnly), "m": .signed(minutes), "t": .bool(twap.randomize),
            ],
        ]
        return try await exchange.perform(action, decoding: Hyperliquid.TwapPlacementResult.self, expiresAfter: expiresAfter)
    }

    func cancel(_ id: Hyperliquid.TwapID, coin: Hyperliquid.Coin, expiresAfter: Date?) async throws
        -> Hyperliquid.CancelResult
    {
        _ = try exchange.requireSigner()
        let asset = try await directory.asset(for: coin).id
        let action: ActionValue = ["type": "twapCancel", "a": .unsigned(UInt64(asset)), "t": .unsigned(id.rawValue)]
        return try await exchange.perform(action, decoding: Hyperliquid.CancelResult.self, expiresAfter: expiresAfter)
    }

    /// The duration as the whole number of minutes the action carries.
    private func wholeMinutes(_ duration: Duration) throws(Hyperliquid.ClientError) -> Int64 {
        let (seconds, attoseconds) = duration.components
        guard attoseconds == 0, seconds % 60 == 0 else {
            throw Hyperliquid.ClientError(.invalidRequest, message: "The TWAP duration \(duration) isn't a whole number of minutes")
        }
        return seconds / 60
    }
}

// MARK: - Requests

extension InfoRequest where Response == [Hyperliquid.TwapSliceFill] {
    static func userTwapSliceFills(_ user: Hyperliquid.Address) -> Self {
        Self("userTwapSliceFills", [userParameter(user)])
    }
}

extension InfoRequest where Response == [Hyperliquid.TwapHistoryEntry] {
    static func twapHistory(_ user: Hyperliquid.Address) -> Self {
        Self("twapHistory", [userParameter(user)])
    }
}
