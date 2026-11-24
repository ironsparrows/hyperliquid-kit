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
