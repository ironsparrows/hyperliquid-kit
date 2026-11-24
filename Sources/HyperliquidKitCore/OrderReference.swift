extension Hyperliquid {
    /// An order to cancel by Hyperliquid's ID.
    public struct OrderReference: Hashable, Sendable {
        public let id: OrderID
        public let coin: Coin

        public init(_ id: OrderID, coin: Coin) {
            self.id = id
            self.coin = coin
        }
    }
}
