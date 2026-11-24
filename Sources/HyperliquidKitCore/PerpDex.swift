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

extension Hyperliquid.PerpDex {
    /// A builder-deployed perp DEX's caps on open interest and transfers.
    public struct Limits: Hashable, Sendable {
        /// The cap on the DEX's total open interest. Hyperliquid's `totalOiCap`.
        public let totalOpenInterestCap: Decimal
        /// The cap on each market's open interest size. Hyperliquid's `oiSzCapPerPerp`.
        public let openInterestSizeCapPerPerpetual: Decimal
        /// The largest notional value a transfer may move. Hyperliquid's `maxTransferNtl`.
        public let maxTransferNotional: Decimal
        /// Each market's cap on open interest.
        public let openInterestCaps: [Hyperliquid.Coin: Decimal]

        public init(
            totalOpenInterestCap: Decimal, openInterestSizeCapPerPerpetual: Decimal, maxTransferNotional: Decimal,
            openInterestCaps: [Hyperliquid.Coin: Decimal] = [:]
        ) {
            self.totalOpenInterestCap = totalOpenInterestCap
            self.openInterestSizeCapPerPerpetual = openInterestSizeCapPerPerpetual
            self.maxTransferNotional = maxTransferNotional
            self.openInterestCaps = openInterestCaps
        }
    }

    /// A perp DEX's net deposits.
    public struct Status: Hashable, Sendable {
        /// The DEX's total net deposits. Hyperliquid's `totalNetDeposit`.
        public let totalNetDeposit: Decimal

        public init(totalNetDeposit: Decimal) {
            self.totalNetDeposit = totalNetDeposit
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dex = .named(try container.decode(String.self, forKey: .name))
        fullName = try container.decode(String.self, forKey: .fullName)
        deployer = try container.decode(Hyperliquid.Address.self, forKey: .deployer)
        oracleUpdater = try container.decodeIfPresent(Hyperliquid.Address.self, forKey: .oracleUpdater)
        feeRecipient = try container.decodeIfPresent(Hyperliquid.Address.self, forKey: .feeRecipient)
        openInterestCaps = try container.decodeIfPresent(CoinValues.self, forKey: .openInterestCaps)?.values ?? [:]
        fundingMultipliers = try container.decodeIfPresent(CoinValues.self, forKey: .fundingMultipliers)?.values ?? [:]
    }
}

extension Hyperliquid.PerpDex.Limits: Decodable {
    private enum CodingKeys: String, CodingKey {
        case totalOiCap, oiSzCapPerPerp, maxTransferNtl, coinToOiCap
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalOpenInterestCap = try container.decode(WireDecimal.self, forKey: .totalOiCap).value
        openInterestSizeCapPerPerpetual = try container.decode(WireDecimal.self, forKey: .oiSzCapPerPerp).value
        maxTransferNotional = try container.decode(WireDecimal.self, forKey: .maxTransferNtl).value
        openInterestCaps = try container.decode(CoinValues.self, forKey: .coinToOiCap).values
    }
}

extension Hyperliquid.PerpDex.Status: Decodable {
    private enum CodingKeys: String, CodingKey {
        case totalNetDeposit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalNetDeposit = try container.decode(WireDecimal.self, forKey: .totalNetDeposit).value
    }
}

/// A per-market list of `[coin, "value"]` pairs; the first value wins if a coin repeats.
private struct CoinValues: Decodable {
    let values: [Hyperliquid.Coin: Decimal]

    init(from decoder: any Decoder) throws {
        let pairs = try decoder.singleValueContainer().decode([Pair].self)
        values = Dictionary(pairs.map { ($0.coin, $0.value) }) { first, _ in first }
    }

    private struct Pair: Decodable {
        let coin: Hyperliquid.Coin
        let value: Decimal

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            coin = try container.decode(Hyperliquid.Coin.self)
            value = try container.decode(WireDecimal.self).value
        }
    }
}
