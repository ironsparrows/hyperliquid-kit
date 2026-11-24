public import Foundation

extension Hyperliquid {
    /// The leverage a perpetual allows at each position size.
    public struct MarginTable: Hashable, Sendable {
        public let description: String
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

        public init(description: String, tiers: [Tier]) {
            self.description = description
            self.tiers = tiers
        }
    }
}

// MARK: - Wire

extension Hyperliquid.MarginTable {
    /// The table with this ID: one of `tables`, or for an ID under 50, which Hyperliquid doesn't
    /// list, one tier from zero at a leverage equal to the ID.
    static func resolving(_ id: Int, in tables: [Int: Self]) -> Self? {
        if let table = tables[id] { return table }
        guard (1..<50).contains(id) else { return nil }
        return Self(description: "", tiers: [Tier(lowerBound: 0, maxLeverage: id)])
    }
}

extension Hyperliquid.MarginTable: Decodable {
    private enum CodingKeys: String, CodingKey {
        case description
        case tiers = "marginTiers"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decode(String.self, forKey: .description)
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
