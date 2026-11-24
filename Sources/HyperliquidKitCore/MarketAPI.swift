public import Foundation

extension Hyperliquid {
    /// Public market data: perpetuals, their trading rules and their market state.
    ///
    /// Reached through ``API/market``. None of these requests needs an account or a signer.
    ///
    /// Requests for one coin check it against its perp DEX's perpetuals before the read is sent,
    /// loading them once per perp DEX, and throw ``ClientError/Reason/unknownCoin`` for a coin that
    /// isn't listed.
    /// Spot and outcome coins, such as `"@107"`, are refused the same way: the client covers
    /// perpetuals only.
    public protocol MarketAPI: Sendable {
        // MARK: Perpetuals

        /// The perpetuals on a perp DEX, in asset-ID order, delisted ones included. (`meta`)
        func perpetuals(dex: PerpDex) async throws -> [Perpetual]

        /// The perpetuals on a perp DEX, each with its market state. (`metaAndAssetCtxs`)
        func perpetualContexts(dex: PerpDex) async throws -> [PerpetualContext]

        /// The perpetuals on every perp DEX, the first perp DEX's first. (`allPerpMetas`)
        func allPerpetuals() async throws -> [Perpetual]

        /// The builder-deployed perp DEXs, in Hyperliquid's order. (`perpDexs`)
        func perpDexs() async throws -> [PerpDex.Details]

        // MARK: Prices and trades

        /// The mid price of every market on a perp DEX. The first perp DEX's answer also holds markets
        /// that aren't perpetuals, such as spot markets. A market with an empty book shows its last
        /// trade price. (`allMids`)
        func mids(dex: PerpDex) async throws -> [Coin: Decimal]

        /// A market's book, at most 20 levels per side, with its price levels grouped to `precision`.
        /// (`l2Book`)
        func orderBook(_ coin: Coin, precision: OrderBook.Precision) async throws -> OrderBook

        /// A market's candles from `start` to `end`, oldest first. Only the most recent 5000 candles
        /// are available. (`candleSnapshot`)
        func candles(_ coin: Coin, interval: Candle.Interval, from start: Date, to end: Date) async throws
            -> [Candle]

        /// A market's most recent trades. (`recentTrades`)
        func recentTrades(_ coin: Coin) async throws -> [Trade]

        // MARK: Funding and limits

        /// A perpetual's funding rates from `start` to `end`, or to now when `end` is `nil`, oldest
        /// first. A response holds at most 500 rates: to read further, ask again from the last one's
        /// time. (`fundingHistory`)
        func fundingHistory(_ coin: Coin, from start: Date, to end: Date?) async throws -> [FundingRate]

        /// The perpetuals on a perp DEX whose open interest is at its cap. (`perpsAtOpenInterestCap`)
        func openInterestCapped(dex: PerpDex) async throws -> [Coin]

        /// Each perpetual's next funding rate on Hyperliquid and other venues, for the first perp DEX
        /// only. (`predictedFundings`)
        func predictedFundings() async throws -> [PredictedFunding]

        /// A builder-deployed perp DEX's caps, or `nil` for the first perp DEX, for which Hyperliquid
        /// reports no limits. (`perpDexLimits`)
        func perpDexLimits(_ dex: PerpDex) async throws -> PerpDex.Limits?

        /// A perp DEX's net deposits; ``PerpDex/first`` is accepted. (`perpDexStatus`)
        func perpDexStatus(_ dex: PerpDex) async throws -> PerpDex.Status

        // MARK: Exchange

        /// Hyperliquid's exchange status. (`exchangeStatus`)
        func exchangeStatus() async throws -> ExchangeStatus
    }
}

// MARK: - Defaults

extension Hyperliquid.MarketAPI {
    public func perpetuals() async throws -> [Hyperliquid.Perpetual] {
        try await perpetuals(dex: .first)
    }

    public func perpetualContexts() async throws -> [Hyperliquid.PerpetualContext] {
        try await perpetualContexts(dex: .first)
    }

    public func mids() async throws -> [Hyperliquid.Coin: Decimal] {
        try await mids(dex: .first)
    }

    /// A market's book at full precision, at most 20 levels per side.
    public func orderBook(_ coin: Hyperliquid.Coin) async throws -> Hyperliquid.OrderBook {
        try await orderBook(coin, precision: .full)
    }

    /// A perpetual's funding rates from `start` to now, oldest first, at most 500.
    public func fundingHistory(_ coin: Hyperliquid.Coin, from start: Date) async throws -> [Hyperliquid.FundingRate] {
        try await fundingHistory(coin, from: start, to: nil)
    }

    public func openInterestCapped() async throws -> [Hyperliquid.Coin] {
        try await openInterestCapped(dex: .first)
    }
}
