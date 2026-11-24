public import Foundation

extension Hyperliquid {
    /// A TWAP order and the status it reached.
    public struct TwapHistoryEntry: Hashable, Sendable {
        public let twapID: TwapID
        public let twap: Twap
        public let status: Twap.Status
        /// Hyperliquid's reason for an ``Twap/Status/error``, when it sends one.
        public let statusDescription: String?
        /// When the TWAP reached the status.
        public let time: Date

        public init(twapID: TwapID, twap: Twap, status: Twap.Status, statusDescription: String? = nil, time: Date) {
            self.twapID = twapID
            self.twap = twap
            self.status = status
            self.statusDescription = statusDescription
            self.time = time
        }
    }
}

// MARK: - Wire

extension Hyperliquid.TwapHistoryEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case twapId, state, status, time
    }

    /// `status` is `{status, description?}`.
    private struct Status: Decodable {
        let status: Hyperliquid.Twap.Status
        let description: String?
    }

    /// `time` is whole seconds, unlike the state's `timestamp` in milliseconds.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        twapID = try container.decode(Hyperliquid.TwapID.self, forKey: .twapId)
        twap = try container.decode(Hyperliquid.Twap.self, forKey: .state)
        let status = try container.decode(Status.self, forKey: .status)
        self.status = status.status
        statusDescription = status.description
        time = Date(timeIntervalSince1970: Double(try container.decode(Int64.self, forKey: .time)))
    }
}
