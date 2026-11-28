extension Hyperliquid {
    /// The most a response holds, for the reads Hyperliquid caps.
    ///
    /// The client sends one request per call and never pages: an app that needs more asks again.
    ///
    /// See [Info endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint).
    public enum ResponseSize {
        /// A read over a time range, such as `fundingHistory`, `userFunding` or `userNonFundingLedgerUpdates`,
        /// returns at most this many items. To read further, ask again from the last one's time.
        public static let timeRange = 500
        /// Only each interval's most recent this many candles are available: a `candleSnapshot` for older
        /// ones returns none.
        public static let candles = 5000
        /// `userFills` returns the most recent this many fills, and `userFillsByTime` at most this many in
        /// one response.
        public static let fills = 2000
        /// `userFillsByTime` reaches only the most recent this many fills.
        public static let fillsAvailable = 10_000
        public static let historicalOrders = 2000
        public static let twapSliceFills = 2000
        public static let bookLevelsPerSide = 20
    }
}
