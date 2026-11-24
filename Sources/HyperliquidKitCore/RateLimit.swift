public import Foundation

extension Hyperliquid {
    /// An account's action allowance: requests grow with the volume it has traded.
    public struct RateLimit: Hashable, Sendable {
        /// The value the account has traded since it started.
        public let cumulativeVolume: Decimal
        /// Requests used beyond those reserved, never below zero.
        public let requestsUsed: Int
        public let requestsCap: Int
        /// Requests reserved beyond those used, never below zero, when Hyperliquid sends it.
        public let requestsSurplus: Int?

        public init(cumulativeVolume: Decimal, requestsUsed: Int, requestsCap: Int, requestsSurplus: Int? = nil) {
            self.cumulativeVolume = cumulativeVolume
            self.requestsUsed = requestsUsed
            self.requestsCap = requestsCap
            self.requestsSurplus = requestsSurplus
        }
    }
}

// MARK: - Wire

extension Hyperliquid.RateLimit: Decodable {
    private enum CodingKeys: String, CodingKey {
        case cumVlm, nRequestsUsed, nRequestsCap, nRequestsSurplus
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cumulativeVolume = try container.decode(WireDecimal.self, forKey: .cumVlm).value
        requestsUsed = try container.decode(Int.self, forKey: .nRequestsUsed)
        requestsCap = try container.decode(Int.self, forKey: .nRequestsCap)
        requestsSurplus = try container.decodeIfPresent(Int.self, forKey: .nRequestsSurplus)
    }
}
