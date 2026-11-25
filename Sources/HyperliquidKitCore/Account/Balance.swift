public import Foundation

extension Hyperliquid {
    /// An account's balance of one token, from its spot clearinghouse.
    ///
    /// In unified-account and portfolio-margin mode these balances hold everything the account has,
    /// perp margin included; see ``AccountMode``.
    public struct Balance: Hashable, Sendable {
        /// The token's name as Hyperliquid spells it, such as `"USDC"`.
        public let token: String
        /// The token's index, when Hyperliquid sends one.
        public let tokenIndex: Int?
        public let total: Decimal
        /// The part of ``total`` that is held.
        public let hold: Decimal
        /// Hyperliquid's `entryNtl`: the balance's entry notional value.
        public let entryNotional: Decimal

        public init(token: String, tokenIndex: Int?, total: Decimal, hold: Decimal, entryNotional: Decimal) {
            self.token = token
            self.tokenIndex = tokenIndex
            self.total = total
            self.hold = hold
            self.entryNotional = entryNotional
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Balance: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, token, total, hold, entryNtl
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .coin)
        tokenIndex = try container.decodeIfPresent(Int.self, forKey: .token)
        total = try container.decode(WireDecimal.self, forKey: .total).value
        hold = try container.decode(WireDecimal.self, forKey: .hold).value
        entryNotional = try container.decode(WireDecimal.self, forKey: .entryNtl).value
    }
}

/// `spotClearinghouseState` and a sub-account's `spotState`: `{balances}`.
package struct SpotState: Decodable, Sendable {
    package let balances: [Hyperliquid.Balance]
}
