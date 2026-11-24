public import Foundation

extension Hyperliquid {
    /// A perpetual's next funding rate as each venue predicts it, Hyperliquid's included.
    public struct PredictedFunding: Hashable, Sendable {
        public let coin: Coin
        /// The venues with a prediction for the coin.
        public let venues: [Venue]

        public init(coin: Coin, venues: [Venue]) {
            self.coin = coin
            self.venues = venues
        }
    }
}

extension Hyperliquid.PredictedFunding {
    /// One venue's predicted funding.
    public struct Venue: Hashable, Sendable {
        public let exchange: Exchange
        /// The predicted rate for one funding period. Hyperliquid's own period is an hour; the other
        /// venues' periods aren't stated, so compare rates across venues with care.
        public let rate: Decimal
        /// When the venue next pays funding.
        public let nextFundingTime: Date

        public init(exchange: Exchange, rate: Decimal, nextFundingTime: Date) {
            self.exchange = exchange
            self.rate = rate
            self.nextFundingTime = nextFundingTime
        }
    }
}

// MARK: - Wire

extension Hyperliquid.PredictedFunding: Decodable {
    /// `[coin, [[exchange, {fundingRate, nextFundingTime} or null]]]`; a venue without a prediction
    /// sends `null` and is left out.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        coin = try container.decode(Hyperliquid.Coin.self)
        venues = try container.decode([WireVenue].self).compactMap(\.venue)
    }

    private struct WireVenue: Decodable {
        let venue: Venue?

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let exchange = try container.decode(Exchange.self)
            venue = try container.decode(Prediction?.self).map {
                Venue(exchange: exchange, rate: $0.fundingRate.value, nextFundingTime: $0.nextFundingTime.value)
            }
        }
    }

    private struct Prediction: Decodable {
        let fundingRate: WireDecimal
        let nextFundingTime: WireDate
    }
}
