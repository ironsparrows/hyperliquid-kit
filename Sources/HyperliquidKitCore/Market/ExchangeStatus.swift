public import Foundation

extension Hyperliquid {
    /// The state of Hyperliquid's exchange as it reports it.
    public struct ExchangeStatus: Hashable, Sendable {
        /// Hyperliquid's server time.
        public let time: Date

        public init(time: Date) {
            self.time = time
        }
    }
}

// MARK: - Wire

extension Hyperliquid.ExchangeStatus: Decodable {
    private enum CodingKeys: String, CodingKey {
        case time
    }

    public init(from decoder: any Decoder) throws {
        time = try decoder.container(keyedBy: CodingKeys.self).decode(WireDate.self, forKey: .time).value
    }
}
