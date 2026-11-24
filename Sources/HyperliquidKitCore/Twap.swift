public import Foundation

extension Hyperliquid {
    /// A TWAP order: a size split into slices over a span of minutes.
    public struct Twap: Hashable, Sendable {
        public let coin: Coin
        /// The account that placed it.
        public let user: Address
        public let side: Side
        /// The whole size, in the base coin.
        public let size: Decimal
        /// The size executed so far.
        public let executedSize: Decimal
        /// The value executed so far.
        public let executedNotional: Decimal
        /// How long the TWAP runs.
        public let duration: Duration
        public let reduceOnly: Bool
        /// Whether the slices are randomized.
        public let randomize: Bool
        /// When the TWAP started.
        public let startTime: Date

        public init(
            coin: Coin, user: Address, side: Side, size: Decimal, executedSize: Decimal, executedNotional: Decimal,
            duration: Duration, reduceOnly: Bool, randomize: Bool, startTime: Date
        ) {
            self.coin = coin
            self.user = user
            self.side = side
            self.size = size
            self.executedSize = executedSize
            self.executedNotional = executedNotional
            self.duration = duration
            self.reduceOnly = reduceOnly
            self.randomize = randomize
            self.startTime = startTime
        }
    }
}

extension Hyperliquid.Twap {
    /// Where a TWAP order is in its life.
    public struct Status: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let activated = Self(rawValue: "activated")
        public static let terminated = Self(rawValue: "terminated")
        public static let finished = Self(rawValue: "finished")
        public static let error = Self(rawValue: "error")
        /// Ended by its stop price.
        public static let stopped = Self(rawValue: "stopped")
        public static let waitingForTrigger = Self(rawValue: "waitingForTrigger")
    }
}

// MARK: - Wire

extension Hyperliquid.Twap: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, user, side, sz, executedSz, executedNtl, minutes, reduceOnly, randomize, timestamp
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        user = try container.decode(Hyperliquid.Address.self, forKey: .user)
        side = try container.decode(Hyperliquid.Side.self, forKey: .side)
        size = try container.decode(WireDecimal.self, forKey: .sz).value
        executedSize = try container.decode(WireDecimal.self, forKey: .executedSz).value
        executedNotional = try container.decode(WireDecimal.self, forKey: .executedNtl).value
        duration = .seconds(try container.decode(Int.self, forKey: .minutes) * 60)
        reduceOnly = try container.decode(Bool.self, forKey: .reduceOnly)
        randomize = try container.decode(Bool.self, forKey: .randomize)
        startTime = try container.decode(WireDate.self, forKey: .timestamp).value
    }
}
