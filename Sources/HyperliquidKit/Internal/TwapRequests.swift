import HyperliquidKitCore

/// An account's TWAP orders, read from `/info`.
struct TwapRequests: Hyperliquid.TwapAPI {
    let info: InfoClient
    /// The account a read uses when it is given none.
    let account: Hyperliquid.Address?

    func sliceFills(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.TwapSliceFill] {
        try await info.send(.userTwapSliceFills(try resolveAccount(user, default: account)))
    }

    func history(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.TwapHistoryEntry] {
        try await info.send(.twapHistory(try resolveAccount(user, default: account)))
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
