public import Foundation

extension Hyperliquid {
    /// A family of perpetual order books.
    ///
    /// The first perp DEX is validator-operated. The others are builder-deployed (HIP-3), and their
    /// coins carry the DEX's name as a prefix, as in `"xyz:XYZ100"`.
    public struct PerpDex: Hashable, Sendable, Codable {
        /// The name that prefixes the DEX's coins; empty for the first perp DEX.
        public let name: String

        /// The validator-operated perp DEX.
        public static let first = Self(name: "")

        /// The builder-deployed perp DEX with this name.
        public static func named(_ name: String) -> Self {
            Self(name: name)
        }

        private init(name: String) {
            self.name = name
        }

        public init(from decoder: any Decoder) throws {
            name = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(name)
        }
    }
}

extension Hyperliquid.PerpDex {
    /// A builder-deployed perp DEX as Hyperliquid lists it.
    public struct Details: Hashable, Sendable {
        public let dex: Hyperliquid.PerpDex
        public let fullName: String
        public let deployer: Hyperliquid.Address
        /// The address that updates the DEX's oracle prices, when one is set.
        public let oracleUpdater: Hyperliquid.Address?
        /// The address that receives the DEX's fees, when one is set.
        public let feeRecipient: Hyperliquid.Address?
        /// Each market's cap on open interest.
        public let openInterestCaps: [Hyperliquid.Coin: Decimal]
        /// Each market's multiplier on the funding rate.
        public let fundingMultipliers: [Hyperliquid.Coin: Decimal]

        public init(
            dex: Hyperliquid.PerpDex, fullName: String, deployer: Hyperliquid.Address,
            oracleUpdater: Hyperliquid.Address? = nil, feeRecipient: Hyperliquid.Address? = nil,
            openInterestCaps: [Hyperliquid.Coin: Decimal] = [:], fundingMultipliers: [Hyperliquid.Coin: Decimal] = [:]
        ) {
            self.dex = dex
            self.fullName = fullName
            self.deployer = deployer
            self.oracleUpdater = oracleUpdater
            self.feeRecipient = feeRecipient
            self.openInterestCaps = openInterestCaps
            self.fundingMultipliers = fundingMultipliers
        }
    }
}

// MARK: - Wire

extension Hyperliquid.PerpDex.Details: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, fullName, deployer, oracleUpdater, feeRecipient
        case openInterestCaps = "assetToStreamingOiCap"
        case fundingMultipliers = "assetToFundingMultiplier"
    }

    /// One `[coin, "value"]` pair of a per-market list.
    private struct CoinValue: Decodable {
        let coin: Hyperliquid.Coin
        let value: Decimal

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            coin = try container.decode(Hyperliquid.Coin.self)
            value = try container.decode(WireDecimal.self).value
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func values(_ key: CodingKeys) throws -> [Hyperliquid.Coin: Decimal] {
            let pairs = try container.decodeIfPresent([CoinValue].self, forKey: key) ?? []
            return Dictionary(pairs.map { ($0.coin, $0.value) }) { first, _ in first }
        }
        dex = .named(try container.decode(String.self, forKey: .name))
        fullName = try container.decode(String.self, forKey: .fullName)
        deployer = try container.decode(Hyperliquid.Address.self, forKey: .deployer)
        oracleUpdater = try container.decodeIfPresent(Hyperliquid.Address.self, forKey: .oracleUpdater)
        feeRecipient = try container.decodeIfPresent(Hyperliquid.Address.self, forKey: .feeRecipient)
        openInterestCaps = try values(.openInterestCaps)
        fundingMultipliers = try values(.fundingMultipliers)
    }
}
