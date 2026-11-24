public import Foundation

extension Hyperliquid {
    /// One funding payment on an account's position.
    public struct FundingPayment: Hashable, Sendable {
        public let time: Date
        /// The transaction's hash. Reads always have it; stream pushes don't carry it, so it is `nil`
        /// there.
        public let hash: TransactionHash?
        public let coin: Coin
        /// The amount: positive when the account received funding, negative when it paid.
        /// Hyperliquid's `usdc`.
        public let usdc: Decimal
        /// The position's size in the base coin when funding was paid: positive for a long, negative
        /// for a short.
        public let positionSize: Decimal
        public let rate: Decimal
        /// Hyperliquid's `nSamples`, when it sends a number. Its meaning isn't documented.
        public let sampleCount: Int?

        public init(
            time: Date, hash: TransactionHash?, coin: Coin, usdc: Decimal, positionSize: Decimal, rate: Decimal,
            sampleCount: Int? = nil
        ) {
            self.time = time
            self.hash = hash
            self.coin = coin
            self.usdc = usdc
            self.positionSize = positionSize
            self.rate = rate
            self.sampleCount = sampleCount
        }
    }
}

// MARK: - Wire

extension Hyperliquid.FundingPayment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case time, hash, delta
    }

    /// The payment's own fields: `{coin, usdc, szi, fundingRate, nSamples}`.
    private struct Payment: Decodable {
        let coin: Hyperliquid.Coin
        let usdc: WireDecimal
        let szi: WireDecimal
        let fundingRate: WireDecimal
        let nSamples: Int?
    }

    /// A read's payment nests its fields in `delta` beside `time` and `hash`; a stream's payment has
    /// them beside `time`, without a hash.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(WireDate.self, forKey: .time).value
        hash = try container.decodeIfPresent(Hyperliquid.TransactionHash.self, forKey: .hash)
        let payment = container.contains(.delta)
            ? try container.decode(Payment.self, forKey: .delta) : try Payment(from: decoder)
        coin = payment.coin
        usdc = payment.usdc.value
        positionSize = payment.szi.value
        rate = payment.fundingRate.value
        sampleCount = payment.nSamples
    }
}
