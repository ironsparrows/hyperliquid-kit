extension Hyperliquid {
    /// An order to cancel by the app's client order ID.
    public struct ClientOrderReference: Hashable, Sendable {
        public let clientID: ClientOrderID
        public let coin: Coin

        public init(_ clientID: ClientOrderID, coin: Coin) {
            self.clientID = clientID
            self.coin = coin
        }
    }
}
