public import Foundation

extension Hyperliquid {
    /// What an account can trade in one perpetual at its current leverage.
    public struct TradingLimits: Hashable, Sendable {
        public let coin: Coin
        public let leverage: Leverage
        /// Hyperliquid's `rawUsd`, sent only for isolated margin. Its meaning isn't documented.
        public let rawUSD: Decimal?
        /// The largest order sizes: two values, in the order Hyperliquid sends them. Hyperliquid's docs
        /// don't say which side each value is for.
        public let maxTradeSizes: [Decimal]
        /// What is available to trade: two values, in the order Hyperliquid sends them. Hyperliquid's
        /// docs don't say which side each value is for.
        public let availableToTrade: [Decimal]
        public let markPrice: Decimal

        public init(
            coin: Coin, leverage: Leverage, rawUSD: Decimal? = nil, maxTradeSizes: [Decimal],
            availableToTrade: [Decimal], markPrice: Decimal
        ) {
            self.coin = coin
            self.leverage = leverage
            self.rawUSD = rawUSD
            self.maxTradeSizes = maxTradeSizes
            self.availableToTrade = availableToTrade
            self.markPrice = markPrice
        }
    }
}

// MARK: - Wire

extension Hyperliquid.TradingLimits: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, leverage, maxTradeSzs, availableToTrade, markPx
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        let leverage = try container.decode(WireLeverage.self, forKey: .leverage)
        self.leverage = leverage.leverage
        rawUSD = leverage.rawUSD
        maxTradeSizes = try container.decode([WireDecimal].self, forKey: .maxTradeSzs).map(\.value)
        availableToTrade = try container.decode([WireDecimal].self, forKey: .availableToTrade).map(\.value)
        markPrice = try container.decode(WireDecimal.self, forKey: .markPx).value
    }
}
