extension Hyperliquid {
    /// An order by Hyperliquid's ID and its coin: one to cancel, or one Hyperliquid canceled.
    public struct OrderReference: Hashable, Sendable {
        public let id: OrderID
        public let coin: Coin

        public init(_ id: OrderID, coin: Coin) {
            self.id = id
            self.coin = coin
        }
    }
}

// MARK: - Wire

extension Hyperliquid.OrderReference: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, oid
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Hyperliquid.OrderID.self, forKey: .oid)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
    }
}
