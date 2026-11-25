extension Hyperliquid {
    /// What happened to a TWAP order when it was placed.
    public struct TwapPlacementResult: Hashable, Sendable {
        /// The running TWAP's ID; `nil` when it was rejected.
        public let twapID: TwapID?
        /// Hyperliquid's reason when it was rejected, such as `Invalid TWAP duration: 1 min(s)`.
        public let error: String?

        public init(twapID: TwapID?, error: String?) {
            self.twapID = twapID
            self.error = error
        }

        /// Whether Hyperliquid accepted and started the TWAP.
        public var isRunning: Bool { twapID != nil }
    }
}

// MARK: - Wire

extension Hyperliquid.TwapPlacementResult: Decodable {
    private enum CodingKeys: String, CodingKey {
        case running, error
    }

    private struct Running: Decodable {
        let twapId: Hyperliquid.TwapID
    }

    /// `{"running": {"twapId": …}}` or `{"error": "…"}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let running = try container.decodeIfPresent(Running.self, forKey: .running) {
            self.init(twapID: running.twapId, error: nil)
        } else {
            self.init(twapID: nil, error: try container.decode(String.self, forKey: .error))
        }
    }
}
