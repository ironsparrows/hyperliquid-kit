public import Foundation

extension Hyperliquid {
    /// A perpetual's funding rate at one funding time.
    public struct FundingRate: Hashable, Sendable {
        public let coin: Coin
        /// The hourly rate a long position pays a short one; negative when shorts pay longs.
        public let rate: Decimal
        /// The premium of the impact prices over the oracle price that the rate came from.
        public let premium: Decimal
        public let time: Date

        public init(coin: Coin, rate: Decimal, premium: Decimal, time: Date) {
            self.coin = coin
            self.rate = rate
            self.premium = premium
            self.time = time
        }
    }
}

// MARK: - Wire

extension Hyperliquid.FundingRate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, fundingRate, premium, time
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        rate = try container.decode(WireDecimal.self, forKey: .fundingRate).value
        premium = try container.decode(WireDecimal.self, forKey: .premium).value
        time = try container.decode(WireDate.self, forKey: .time).value
    }
}
