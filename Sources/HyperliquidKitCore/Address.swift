extension Hyperliquid {
    /// An account, API wallet or vault address: `0x` and 40 hexadecimal digits.
    ///
    /// Stored lower-cased, the form Hyperliquid signs and compares, so two spellings of one address
    /// are equal. A mixed-case (checksummed) address is accepted without checking its checksum.
    public struct Address: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
        /// `0x` and 40 lower-case hexadecimal digits.
        public let description: String

        /// Creates an address from `0x` and 40 hexadecimal digits in either case.
        ///
        /// - Throws: ``Hyperliquid/ClientError`` with reason ``Hyperliquid/ClientError/Reason/invalidAddress``.
        ///   The error doesn't repeat `string`, which could be a private key pasted by mistake.
        public init(_ string: String) throws {
            guard isPrefixedHexadecimal(string, digitCount: 40) else {
                throw ClientError(.invalidAddress, message: hexadecimalExpectation(digitCount: 40, for: string))
            }
            description = string.lowercased()
        }

        /// Creates an address from a literal, and stops the program if the literal isn't one.
        public init(stringLiteral value: String) {
            do {
                try self.init(value)
            } catch {
                fatalError("Not an address. \(hexadecimalExpectation(digitCount: 40, for: value))")
            }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            do {
                try self.init(string)
            } catch {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an address. \(hexadecimalExpectation(digitCount: 40, for: string))"
                )
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }
    }
}
