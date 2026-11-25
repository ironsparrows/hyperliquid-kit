public import Foundation

extension Hyperliquid {
    /// An order with where it is in its life: open, filled, or why it was canceled or rejected.
    public struct HistoricalOrder: Hashable, Sendable {
        public let order: Order
        public let status: OrderStatus
        /// When the order reached its status.
        public let statusTime: Date

        public init(order: Order, status: OrderStatus, statusTime: Date) {
            self.order = order
            self.status = status
            self.statusTime = statusTime
        }
    }
}

// MARK: - Wire

extension Hyperliquid.HistoricalOrder: Decodable {
    private enum CodingKeys: String, CodingKey {
        case order, status, statusTimestamp
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decode(Hyperliquid.Order.self, forKey: .order)
        status = try container.decode(Hyperliquid.OrderStatus.self, forKey: .status)
        statusTime = try container.decode(WireDate.self, forKey: .statusTimestamp).value
    }
}

/// `orderStatus`: `{"status": "order", "order": {order, status, statusTimestamp}}`, or
/// `{"status": "unknownOid"}` for an order Hyperliquid doesn't know.
package struct OrderStatusResponse: Decodable, Sendable {
    package let order: Hyperliquid.HistoricalOrder?

    private enum CodingKeys: String, CodingKey {
        case status, order
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .status) {
        case "order":
            order = try container.decode(Hyperliquid.HistoricalOrder.self, forKey: .order)
        case "unknownOid":
            order = nil
        case let status:
            throw DecodingError.dataCorruptedError(
                forKey: .status, in: container, debugDescription: "Unknown order status response: \(status)"
            )
        }
    }
}
