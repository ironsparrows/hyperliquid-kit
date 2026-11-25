import Foundation

extension Hyperliquid {
    /// A position's leverage and how it is margined, such as `.cross(10)` or `.isolated(3)`.
    public struct Leverage: Hashable, Sendable {
        public let mode: MarginMode
        public let value: Int

        package init(mode: MarginMode, value: Int) {
            self.mode = mode
            self.value = value
        }

        /// Leverage on the perp DEX's cross margin.
        public static func cross(_ value: Int) -> Self {
            Self(mode: .cross, value: value)
        }

        /// Leverage on margin set aside for the one position.
        public static func isolated(_ value: Int) -> Self {
            Self(mode: .isolated, value: value)
        }
    }
}

// MARK: - Wire

/// `{type, value, rawUsd?}`, where `rawUsd` comes only with isolated margin.
struct WireLeverage: Decodable {
    let leverage: Hyperliquid.Leverage
    let rawUSD: Decimal?

    private enum CodingKeys: String, CodingKey {
        case type, value, rawUsd
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leverage = Hyperliquid.Leverage(
            mode: try container.decode(Hyperliquid.MarginMode.self, forKey: .type),
            value: try container.decode(Int.self, forKey: .value)
        )
        rawUSD = try container.decodeIfPresent(WireDecimal.self, forKey: .rawUsd)?.value
    }
}
