public import Foundation

extension Hyperliquid {
    /// A market's best bid and ask.
    public struct BestBidOffer: Hashable, Sendable {
        public let coin: Coin
        public let time: Date
        /// The best buy level, or `nil` when the book has no bids.
        public let bid: OrderBook.Level?
        /// The best sell level, or `nil` when the book has no asks.
        public let ask: OrderBook.Level?

        public init(coin: Coin, time: Date, bid: OrderBook.Level?, ask: OrderBook.Level?) {
            self.coin = coin
            self.time = time
            self.bid = bid
            self.ask = ask
        }
    }
}

// MARK: - Wire

extension Hyperliquid.BestBidOffer: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, time, bbo
    }

    /// `bbo` is `[bid or null, ask or null]`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        time = try container.decode(WireDate.self, forKey: .time).value
        var levels = try container.nestedUnkeyedContainer(forKey: .bbo)
        bid = try levels.decode(Hyperliquid.OrderBook.Level?.self)
        ask = try levels.decode(Hyperliquid.OrderBook.Level?.self)
    }
}
