extension Hyperliquid {
    /// A perpetual market and its trading rules.
    public struct Perpetual: Hashable, Sendable {
        /// The market's name; on a builder-deployed perp DEX it starts with the DEX's name.
        public let name: Coin
        /// How many decimals a size may have.
        public let sizeDecimals: Int
        public let maxLeverage: Int
        /// The leverage allowed at each position size, or `nil` when Hyperliquid names no table.
        public let marginTable: MarginTable?
        /// The margining the market restricts positions to, or `nil` when it allows cross margin.
        public let marginMode: MarginMode?
        /// Whether the market is delisted. Delisted markets stay in the list, so asset IDs don't move.
        public let isDelisted: Bool

        public init(
            name: Coin, sizeDecimals: Int, maxLeverage: Int, marginTable: MarginTable?, marginMode: MarginMode? = nil,
            isDelisted: Bool = false
        ) {
            self.name = name
            self.sizeDecimals = sizeDecimals
            self.maxLeverage = maxLeverage
            self.marginTable = marginTable
            self.marginMode = marginMode
            self.isDelisted = isDelisted
        }
    }
}

// MARK: - Wire

/// A perp DEX's `meta`: its perpetuals in asset-ID order, with their margin tables resolved.
package struct PerpetualMetadata: Decodable, Sendable {
    package let perpetuals: [Hyperliquid.Perpetual]

    private enum CodingKeys: String, CodingKey {
        case universe, marginTables
    }

    private struct Entry: Decodable {
        let name: Hyperliquid.Coin
        let szDecimals: Int
        let maxLeverage: Int
        let marginTableId: Int?
        let marginMode: Hyperliquid.MarginMode?
        let isDelisted: Bool?
    }

    private struct NumberedTable: Decodable {
        let id: Int
        let table: Hyperliquid.MarginTable

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            id = try container.decode(Int.self)
            table = try container.decode(Hyperliquid.MarginTable.self)
        }
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tables = try container.decode([NumberedTable].self, forKey: .marginTables)
        let tablesByID = Dictionary(tables.map { ($0.id, $0.table) }) { first, _ in first }
        perpetuals = try container.decode([Entry].self, forKey: .universe).map { entry in
            let marginTable = try entry.marginTableId.map { id in
                guard let table = Hyperliquid.MarginTable.resolving(id, in: tablesByID) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .marginTables, in: container, debugDescription: "No margin table \(id) for \(entry.name)"
                    )
                }
                return table
            }
            return Hyperliquid.Perpetual(
                name: entry.name,
                sizeDecimals: entry.szDecimals,
                maxLeverage: entry.maxLeverage,
                marginTable: marginTable,
                marginMode: entry.marginMode,
                isDelisted: entry.isDelisted ?? false
            )
        }
    }
}
