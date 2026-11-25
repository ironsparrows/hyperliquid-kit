public import Foundation

extension Hyperliquid {
    /// One public execution in a market.
    public struct Trade: Hashable, Sendable {
        public let coin: Coin
        public let side: Side
        public let price: Decimal
        /// The traded size, in the base coin.
        public let size: Decimal
        public let time: Date
        public let hash: TransactionHash
        public let id: TradeID
        public let buyer: Address
        public let seller: Address

        public init(
            coin: Coin, side: Side, price: Decimal, size: Decimal, time: Date, hash: TransactionHash, id: TradeID,
            buyer: Address, seller: Address
        ) {
            self.coin = coin
            self.side = side
            self.price = price
            self.size = size
            self.time = time
            self.hash = hash
            self.id = id
            self.buyer = buyer
            self.seller = seller
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Trade: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, side, px, sz, time, hash, tid, users
    }

    /// `users` is `[buyer, seller]`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        side = try container.decode(Hyperliquid.Side.self, forKey: .side)
        price = try container.decode(WireDecimal.self, forKey: .px).value
        size = try container.decode(WireDecimal.self, forKey: .sz).value
        time = try container.decode(WireDate.self, forKey: .time).value
        hash = try container.decode(Hyperliquid.TransactionHash.self, forKey: .hash)
        id = try container.decode(Hyperliquid.TradeID.self, forKey: .tid)
        var users = try container.nestedUnkeyedContainer(forKey: .users)
        buyer = try users.decode(Hyperliquid.Address.self)
        seller = try users.decode(Hyperliquid.Address.self)
    }
}
