extension Hyperliquid {
    /// A market's name as Hyperliquid spells it, such as `"BTC"`, `"xyz:XYZ100"` on a builder-deployed
    /// perp DEX, `"@107"` or `"PURR/USDC"` for a spot market, or `"#10"` for an outcome.
    public struct Coin: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
        public let name: String

        public init(_ name: String) {
            self.name = name
        }

        public init(stringLiteral value: String) {
            self.init(value)
        }

        public init(from decoder: any Decoder) throws {
            name = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(name)
        }

        public var description: String { name }

        /// The perp DEX a perpetual trades on: the name before `:`, or ``PerpDex/first`` when there is
        /// no prefix. Meaningless for a spot or outcome coin.
        public var dex: PerpDex {
            guard let colon = name.firstIndex(of: ":") else { return .first }
            return .named(String(name[..<colon]))
        }

        /// Which kind of market the name spells: a name that starts with `#` is an outcome, one that
        /// starts with `@` or names a pair such as `"PURR/USDC"` is a spot market, any other is a
        /// perpetual.
        public var kind: Kind {
            if name.hasPrefix("#") { return .outcome }
            if name.hasPrefix("@") || name.contains("/") { return .spot }
            return .perpetual
        }
    }
}

extension Hyperliquid.Coin {
    /// A kind of market. The client trades and reads market data only for perpetuals; account
    /// responses, mid prices and the prices stream can still hold spot and outcome coins.
    public enum Kind: Hashable, Sendable {
        case perpetual
        case spot
        case outcome
    }
}

// MARK: - Wire

/// A dictionary keyed by coin encodes and decodes as a JSON object keyed by the coin's name, as
/// Hyperliquid sends one, not as an array of alternating keys and values.
extension Hyperliquid.Coin: CodingKeyRepresentable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    public var codingKey: any CodingKey {
        Key(stringValue: name)
    }

    public init?(codingKey: some CodingKey) {
        self.init(codingKey.stringValue)
    }
}
