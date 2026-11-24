extension Hyperliquid {
    /// An order's ID, assigned by Hyperliquid.
    public struct OrderID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        public var description: String { String(rawValue) }
    }

    /// An order ID the app chooses when it places an order: 16 bytes, written as `0x` and 32
    /// hexadecimal digits.
    public struct ClientOrderID: Hashable, Sendable, Codable, CustomStringConvertible {
        /// `0x` and 32 lower-case hexadecimal digits.
        public let description: String

        /// Creates an ID from `0x` and 32 hexadecimal digits in either case.
        ///
        /// - Throws: ``Hyperliquid/ClientError`` with reason
        ///   ``Hyperliquid/ClientError/Reason/invalidClientOrderID``.
        public init(_ hex: String) throws {
            guard isPrefixedHexadecimal(hex, digitCount: 32) else {
                throw ClientError(.invalidClientOrderID, message: hexadecimalExpectation(digitCount: 32, for: hex))
            }
            description = hex.lowercased()
        }

        private init(validated description: String) {
            self.description = description
        }

        /// A new ID from the system's secure random number generator.
        public static func random() -> Self {
            var generator = SystemRandomNumberGenerator()
            let halves = [generator.next(), generator.next()] as [UInt64]
            let digits = halves.map { half in
                let hex = String(half, radix: 16)
                return String(repeating: "0", count: 16 - hex.count) + hex
            }
            return Self(validated: "0x" + digits.joined())
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let hex = try container.decode(String.self)
            do {
                try self.init(hex)
            } catch {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not a client order ID. \(hexadecimalExpectation(digitCount: 32, for: hex))"
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }
    }

    /// A TWAP order's ID, assigned by Hyperliquid.
    public struct TwapID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        public var description: String { String(rawValue) }
    }

    /// The hash of a transaction on Hyperliquid's chain, as `0x` and 64 hexadecimal digits.
    ///
    /// Some trades and TWAP slice fills carry the zero hash.
    public struct TransactionHash: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }
    }
}
