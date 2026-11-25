public import Foundation

extension Hyperliquid {
    /// A market's prices, volume and trade count over one interval.
    public struct Candle: Hashable, Sendable {
        public let coin: Coin
        public let interval: Interval
        /// When the interval starts.
        public let openTime: Date
        /// The last millisecond of the interval.
        public let closeTime: Date
        public let open: Decimal
        public let high: Decimal
        public let low: Decimal
        public let close: Decimal
        /// The traded size, in the base coin.
        public let volume: Decimal
        public let tradeCount: Int

        public init(
            coin: Coin, interval: Interval, openTime: Date, closeTime: Date, open: Decimal, high: Decimal,
            low: Decimal, close: Decimal, volume: Decimal, tradeCount: Int
        ) {
            self.coin = coin
            self.interval = interval
            self.openTime = openTime
            self.closeTime = closeTime
            self.open = open
            self.high = high
            self.low = low
            self.close = close
            self.volume = volume
            self.tradeCount = tradeCount
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Candle: Decodable {
    private enum CodingKeys: String, CodingKey {
        case t, T, s, i, o, h, l, c, v, n
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            try container.decode(WireDecimal.self, forKey: key).value
        }
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .s)
        interval = try container.decode(Interval.self, forKey: .i)
        openTime = try container.decode(WireDate.self, forKey: .t).value
        closeTime = try container.decode(WireDate.self, forKey: .T).value
        open = try decimal(.o)
        high = try decimal(.h)
        low = try decimal(.l)
        close = try decimal(.c)
        volume = try decimal(.v)
        tradeCount = try container.decode(Int.self, forKey: .n)
    }
}
