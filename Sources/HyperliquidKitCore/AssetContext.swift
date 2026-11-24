public import Foundation

extension Hyperliquid {
    /// A perpetual's market state: prices, funding, open interest and the last day's volume.
    public struct AssetContext: Hashable, Sendable {
        public let markPrice: Decimal
        /// The middle of the best bid and ask, or `nil` when the book has no bid or no ask.
        public let midPrice: Decimal?
        public let oraclePrice: Decimal
        /// The price 24 hours ago.
        public let previousDayPrice: Decimal
        /// The current hourly funding rate.
        public let funding: Decimal
        /// The premium of the impact prices over the oracle price, which funding follows, or `nil`
        /// when there is none.
        public let premium: Decimal?
        /// Open interest, in the base coin.
        public let openInterest: Decimal
        /// The last 24 hours' traded value, in the collateral token.
        public let dayNotionalVolume: Decimal
        /// The last 24 hours' traded size, in the base coin, when Hyperliquid sends it.
        public let dayBaseVolume: Decimal?
        /// The average price a sell of the impact notional fills at against the bids, or `nil` without
        /// a book.
        public let impactBidPrice: Decimal?
        /// The average price a buy of the impact notional fills at against the asks, or `nil` without
        /// a book.
        public let impactAskPrice: Decimal?

        public init(
            markPrice: Decimal, midPrice: Decimal?, oraclePrice: Decimal, previousDayPrice: Decimal, funding: Decimal,
            premium: Decimal?, openInterest: Decimal, dayNotionalVolume: Decimal, dayBaseVolume: Decimal?,
            impactBidPrice: Decimal?, impactAskPrice: Decimal?
        ) {
            self.markPrice = markPrice
            self.midPrice = midPrice
            self.oraclePrice = oraclePrice
            self.previousDayPrice = previousDayPrice
            self.funding = funding
            self.premium = premium
            self.openInterest = openInterest
            self.dayNotionalVolume = dayNotionalVolume
            self.dayBaseVolume = dayBaseVolume
            self.impactBidPrice = impactBidPrice
            self.impactAskPrice = impactAskPrice
        }
    }
}

// MARK: - Wire

extension Hyperliquid.AssetContext: Decodable {
    private enum CodingKeys: String, CodingKey {
        case markPx, midPx, oraclePx, prevDayPx, funding, premium, openInterest, dayNtlVlm, dayBaseVlm, impactPxs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            try container.decode(WireDecimal.self, forKey: key).value
        }
        func optionalDecimal(_ key: CodingKeys) throws -> Decimal? {
            try container.decodeIfPresent(WireDecimal.self, forKey: key)?.value
        }
        markPrice = try decimal(.markPx)
        midPrice = try optionalDecimal(.midPx)
        oraclePrice = try decimal(.oraclePx)
        previousDayPrice = try decimal(.prevDayPx)
        funding = try decimal(.funding)
        premium = try optionalDecimal(.premium)
        openInterest = try decimal(.openInterest)
        dayNotionalVolume = try decimal(.dayNtlVlm)
        dayBaseVolume = try optionalDecimal(.dayBaseVlm)
        // `[bid, ask]`, or `null` without a book.
        let impactPrices = try container.decodeIfPresent([WireDecimal].self, forKey: .impactPxs)
        if let impactPrices, impactPrices.count != 2 {
            throw DecodingError.dataCorruptedError(
                forKey: .impactPxs, in: container, debugDescription: "Expected a bid and an ask, got \(impactPrices.count)"
            )
        }
        impactBidPrice = impactPrices?.first?.value
        impactAskPrice = impactPrices?.last?.value
    }
}
