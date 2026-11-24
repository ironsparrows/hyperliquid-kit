public import Foundation

extension Hyperliquid {
    /// An account's positions: what it can trade and the funding it has paid.
    ///
    /// Reached through ``API/position``. Reads take the account's address in `user` as
    /// ``AccountAPI`` does: `nil` means the client's account, and without one the read throws
    /// ``ClientError/Reason/missingAccount``.
    public protocol PositionAPI: Sendable {
        /// What the account can trade in a perpetual at its current leverage. The coin is checked
        /// against its perp DEX's perpetuals first, as ``MarketAPI`` checks it. (`activeAssetData`)
        func tradingLimits(_ coin: Coin, for user: Address?) async throws -> TradingLimits

        /// The funding the account paid or received from `start` to `end`, or to now when `end` is
        /// `nil`, oldest first. A response holds a limited number of payments: to read further, ask
        /// again from the last one's time. (`userFunding`)
        func fundingPayments(from start: Date, to end: Date?, for user: Address?) async throws -> [FundingPayment]
    }
}

// MARK: - Defaults

extension Hyperliquid.PositionAPI {
    public func tradingLimits(_ coin: Hyperliquid.Coin) async throws -> Hyperliquid.TradingLimits {
        try await tradingLimits(coin, for: nil)
    }

    /// The client's account's funding payments from `start` to `end`, oldest first.
    public func fundingPayments(from start: Date, to end: Date) async throws -> [Hyperliquid.FundingPayment] {
        try await fundingPayments(from: start, to: end, for: nil)
    }

    /// An account's funding payments from `start` to now, oldest first.
    public func fundingPayments(from start: Date, for user: Hyperliquid.Address? = nil) async throws
        -> [Hyperliquid.FundingPayment]
    {
        try await fundingPayments(from: start, to: nil, for: user)
    }
}
