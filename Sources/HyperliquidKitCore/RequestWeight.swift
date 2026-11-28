extension Hyperliquid {
    /// What each REST request weighs against the weight Hyperliquid lets each IP spend a minute.
    ///
    /// The client doesn't count weight or wait for it: these are for an app that paces its own
    /// requests. Actions also count against the account's own allowance, which
    /// ``Hyperliquid/AccountAPI/rateLimit(for:)`` reads.
    ///
    /// See [Rate limits and user limits](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/rate-limits-and-user-limits).
    public enum RequestWeight {
        /// The weight one IP may spend a minute, on `info` and `exchange` requests together.
        public static let perMinute = 1200

        // MARK: Reads

        /// Every `info` request but those below.
        public static let info = 20
        /// `l2Book`, `allMids`, `clearinghouseState`, `orderStatus`, `spotClearinghouseState` and `exchangeStatus`.
        public static let lightInfo = 2
        public static let userRole = 60
        /// `recentTrades`, `historicalOrders`, `userFills`, `userFillsByTime`, `fundingHistory`, `userFunding`,
        /// `twapHistory` and `userTwapSliceFills` weigh extra for every this many items they return.
        public static let itemsPerExtraWeight = 20
        /// `candleSnapshot` weighs extra for every this many candles it returns.
        public static let candlesPerExtraWeight = 60

        // MARK: Actions

        /// An action weighs this much, plus 1 for every ``batchLengthPerExtraWeight`` orders, cancels or
        /// changes it batches.
        public static let action = 1
        public static let batchLengthPerExtraWeight = 40
    }
}
