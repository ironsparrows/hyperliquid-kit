public import Foundation

extension Hyperliquid {
    /// What happened to one order of a placement or modification.
    ///
    /// Hyperliquid answers every order separately: one can be rejected while the others rest or fill.
    /// A status Hyperliquid adds later keeps its name in ``Status/rawValue``.
    public struct PlacementResult: Hashable, Sendable {
        public let status: Status
        /// The order's ID, unless it was rejected or waits.
        public let orderID: OrderID?
        public let clientID: ClientOrderID?
        /// The size filled at once, for a filled order.
        public let filledSize: Decimal?
        /// The average fill price, for a filled order.
        public let averagePrice: Decimal?
        /// Hyperliquid's reason, for a rejected order, such as `Order must have minimum value of $10.`
        public let error: String?

        public init(
            status: Status, orderID: OrderID? = nil, clientID: ClientOrderID? = nil, filledSize: Decimal? = nil,
            averagePrice: Decimal? = nil, error: String? = nil
        ) {
            self.status = status
            self.orderID = orderID
            self.clientID = clientID
            self.filledSize = filledSize
            self.averagePrice = averagePrice
            self.error = error
        }

        /// An order's outcome.
        public struct Status: RawRepresentable, Hashable, Sendable, Codable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            /// On the book.
            public static let resting = Self(rawValue: "resting")
            /// Filled at once.
            public static let filled = Self(rawValue: "filled")
            /// Rejected; ``PlacementResult/error`` says why.
            public static let rejected = Self(rawValue: "error")
        }
    }
}

// MARK: - Wire

extension Hyperliquid.PlacementResult: Decodable {
    private struct Details: Decodable {
        let oid: Hyperliquid.OrderID?
        let cloid: Hyperliquid.ClientOrderID?
        let totalSz: WireDecimal?
        let avgPx: WireDecimal?
    }

    /// A status: a bare string such as `"waitingForFill"`, or an object with one key such as
    /// `{"resting": {"oid": 1}}` or `{"error": "…"}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let status = try? container.decode(String.self) {
            self.init(status: Status(rawValue: status))
            return
        }
        let object = try container.decode([String: AnyDetails].self)
        guard object.count == 1, let (key, value) = object.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected one status, got \(object.keys)")
        }
        switch value {
        case .message(let message):
            self.init(status: Status(rawValue: key), error: message)
        case .details(let details):
            self.init(
                status: Status(rawValue: key), orderID: details.oid, clientID: details.cloid,
                filledSize: details.totalSz?.value, averagePrice: details.avgPx?.value
            )
        }
    }

    private enum AnyDetails: Decodable {
        case message(String)
        case details(Details)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let message = try? container.decode(String.self) {
                self = .message(message)
            } else {
                self = .details(try container.decode(Details.self))
            }
        }
    }
}
