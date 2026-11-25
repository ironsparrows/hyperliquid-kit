public import Foundation

extension Hyperliquid {
    /// The leverage a perpetual allows at each position size.
    public struct MarginTable: Hashable, Sendable {
        /// Hyperliquid's name for the table, such as `"tiered 10x"`; it may be empty.
        public let name: String
        /// The tiers, from the smallest position up.
        public let tiers: [Tier]

        /// The leverage allowed from one position value up to the next tier's.
        public struct Tier: Hashable, Sendable {
            /// The position value, in the collateral token, where the tier starts.
            public let lowerBound: Decimal
            public let maxLeverage: Int

            public init(lowerBound: Decimal, maxLeverage: Int) {
                self.lowerBound = lowerBound
                self.maxLeverage = maxLeverage
            }
        }

        public init(name: String, tiers: [Tier]) {
            self.name = name
            self.tiers = tiers
        }
    }
}

// MARK: - Wire

extension Hyperliquid.MarginTable: Decodable {
    private enum CodingKeys: String, CodingKey {
        case description
        case tiers = "marginTiers"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .description)
        tiers = try container.decode([Tier].self, forKey: .tiers)
    }
}

extension Hyperliquid.MarginTable.Tier: Decodable {
    private enum CodingKeys: String, CodingKey {
        case lowerBound, maxLeverage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lowerBound = try container.decode(WireDecimal.self, forKey: .lowerBound).value
        maxLeverage = try container.decode(Int.self, forKey: .maxLeverage)
    }
}
