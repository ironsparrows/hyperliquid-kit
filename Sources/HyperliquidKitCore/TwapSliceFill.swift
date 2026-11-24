extension Hyperliquid {
    /// A fill of one TWAP slice.
    public struct TwapSliceFill: Hashable, Sendable {
        public let fill: Fill
        public let twapID: TwapID

        public init(fill: Fill, twapID: TwapID) {
            self.fill = fill
            self.twapID = twapID
        }
    }
}

// MARK: - Wire

extension Hyperliquid.TwapSliceFill: Decodable {
    private enum CodingKeys: String, CodingKey {
        case fill, twapId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fill = try container.decode(Hyperliquid.Fill.self, forKey: .fill)
        twapID = try container.decode(Hyperliquid.TwapID.self, forKey: .twapId)
    }
}
