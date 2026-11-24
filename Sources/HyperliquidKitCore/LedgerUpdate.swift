public import Foundation

extension Hyperliquid {
    /// A change to an account's balances other than funding: a deposit, transfer, withdrawal and so on.
    ///
    /// Hyperliquid doesn't document each kind's fields, so only the time, hash, kind and USDC amount
    /// are read. The amount is unsigned as Hyperliquid sends it; who sent and who received isn't read,
    /// so a transfer's direction can't be told from it.
    public struct LedgerUpdate: Hashable, Sendable {
        public let time: Date
        public let hash: TransactionHash
        public let kind: Kind
        /// The USDC amount, for kinds that move USDC.
        public let usdc: Decimal?

        public init(time: Date, hash: TransactionHash, kind: Kind, usdc: Decimal? = nil) {
            self.time = time
            self.hash = hash
            self.kind = kind
            self.usdc = usdc
        }
    }
}

extension Hyperliquid.LedgerUpdate {
    /// What kind of change it was, as Hyperliquid names it.
    public struct Kind: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let deposit = Self(rawValue: "deposit")
        public static let accountClassTransfer = Self(rawValue: "accountClassTransfer")
        /// USDC sent between accounts.
        public static let internalTransfer = Self(rawValue: "internalTransfer")
        /// A spot token sent between accounts.
        public static let spotTransfer = Self(rawValue: "spotTransfer")
        public static let spotGenesis = Self(rawValue: "spotGenesis")
    }
}

// MARK: - Wire

extension Hyperliquid.LedgerUpdate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case time, hash, delta
    }

    /// `delta` is `{type, …}`, with fields that depend on `type`.
    private struct Delta: Decodable {
        let type: Kind
        let usdc: WireDecimal?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(WireDate.self, forKey: .time).value
        hash = try container.decode(Hyperliquid.TransactionHash.self, forKey: .hash)
        let delta = try container.decode(Delta.self, forKey: .delta)
        kind = delta.type
        usdc = delta.usdc?.value
    }
}
