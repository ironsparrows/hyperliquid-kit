public import Foundation

extension Hyperliquid {
    /// The best price levels on each side of a market's book, at most 20 per side.
    public struct OrderBook: Hashable, Sendable {
        public let coin: Coin
        public let time: Date
        /// Buy orders, best (highest) price first.
        public let bids: [Level]
        /// Sell orders, best (lowest) price first.
        public let asks: [Level]

        public init(coin: Coin, time: Date, bids: [Level], asks: [Level]) {
            self.coin = coin
            self.time = time
            self.bids = bids
            self.asks = asks
        }
    }
}

extension Hyperliquid.OrderBook {
    /// The orders resting at one price.
    public struct Level: Hashable, Sendable {
        public let price: Decimal
        /// The size of all orders at this price, in the base coin.
        public let size: Decimal
        /// How many orders rest at this price, when Hyperliquid sends it.
        public let orderCount: Int?

        public init(price: Decimal, size: Decimal, orderCount: Int?) {
            self.price = price
            self.size = size
            self.orderCount = orderCount
        }
    }
}

extension Hyperliquid.OrderBook {
    /// How finely a book's price levels are grouped.
    ///
    /// Only the combinations Hyperliquid accepts can be written: 2 to 5 significant figures, and a
    /// mantissa only with 5.
    public enum Precision: Hashable, Sendable {
        /// Every price level as it rests.
        case full
        /// Prices grouped to a number of significant figures.
        case significantFigures(SignificantFigures)
        /// Prices grouped to 5 significant figures, in steps of the mantissa in the last figure.
        case fiveSignificantFigures(mantissa: Mantissa)

        /// How many significant figures prices are grouped to.
        public enum SignificantFigures: Int, Sendable, CaseIterable {
            case two = 2
            case three, four, five
        }

        /// The step, in the last of 5 significant figures, that prices are grouped by.
        public enum Mantissa: Int, Sendable, CaseIterable {
            case one = 1
            case two = 2
            case five = 5
        }
    }
}

// MARK: - Wire

extension Hyperliquid.OrderBook: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, time, levels
    }

    /// `levels` is `[bids, asks]`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        time = try container.decode(WireDate.self, forKey: .time).value
        var levels = try container.nestedUnkeyedContainer(forKey: .levels)
        bids = try levels.decode([Level].self)
        asks = try levels.decode([Level].self)
    }
}

extension Hyperliquid.OrderBook.Level: Decodable {
    private enum CodingKeys: String, CodingKey {
        case px, sz, n
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        price = try container.decode(WireDecimal.self, forKey: .px).value
        size = try container.decode(WireDecimal.self, forKey: .sz).value
        orderCount = try container.decodeIfPresent(Int.self, forKey: .n)
    }
}
