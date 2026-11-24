extension Hyperliquid {
    /// A market's name as Hyperliquid spells it, such as `"BTC"`, or `"xyz:XYZ100"` on a
    /// builder-deployed perp DEX.
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
