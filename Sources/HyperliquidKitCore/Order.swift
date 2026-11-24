public import Foundation

extension Hyperliquid {
    /// An order as Hyperliquid reports it: pending, or in an order's history.
    ///
    /// On the first perp DEX an account's orders include spot orders, such as `"@107"`; ``coin``'s
    /// ``Coin/kind`` tells them apart.
    public struct Order: Hashable, Sendable {
        public let coin: Coin
        public let side: Side
        public let limitPrice: Decimal
        /// The size still open, in the base coin.
        public let size: Decimal
        public let id: OrderID
        /// When the order was placed.
        public let time: Date
        /// The app's ID for the order, when it set one and Hyperliquid sends it.
        public let clientID: ClientOrderID?
        /// How the order was placed, when the read returns it; `nil` from
        /// ``OrderAPI/pending(dex:for:)``.
        public let details: Details?

        public init(
            coin: Coin, side: Side, limitPrice: Decimal, size: Decimal, id: OrderID, time: Date,
            clientID: ClientOrderID? = nil, details: Details? = nil
        ) {
            self.coin = coin
            self.side = side
            self.limitPrice = limitPrice
            self.size = size
            self.id = id
            self.time = time
            self.clientID = clientID
            self.details = details
        }
    }
}

extension Hyperliquid.Order {
    /// How an order was placed: its type, original size, trigger and linked orders.
    public struct Details: Hashable, Sendable {
        public let kind: Kind
        /// The size when the order was placed.
        public let originalSize: Decimal
        /// How long the order rests, when Hyperliquid sends it.
        public let timeInForce: Hyperliquid.TimeInForce?
        public let reduceOnly: Bool
        public let isTrigger: Bool
        public let triggerPrice: Decimal
        /// The trigger as text for display, such as `"Price above 10.004"` or `"N/A"`.
        public let triggerCondition: String
        /// Whether the order is a position take-profit or stop-loss. Hyperliquid's `isPositionTpsl`.
        public let isPositionTakeProfitStopLoss: Bool
        /// Orders linked to this one. Hyperliquid's `children`.
        public let children: [Hyperliquid.Order]

        public init(
            kind: Kind, originalSize: Decimal, timeInForce: Hyperliquid.TimeInForce?, reduceOnly: Bool,
            isTrigger: Bool, triggerPrice: Decimal, triggerCondition: String, isPositionTakeProfitStopLoss: Bool,
            children: [Hyperliquid.Order] = []
        ) {
            self.kind = kind
            self.originalSize = originalSize
            self.timeInForce = timeInForce
            self.reduceOnly = reduceOnly
            self.isTrigger = isTrigger
            self.triggerPrice = triggerPrice
            self.triggerCondition = triggerCondition
            self.isPositionTakeProfitStopLoss = isPositionTakeProfitStopLoss
            self.children = children
        }
    }

    /// An order's type as Hyperliquid names it for display.
    public struct Kind: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let limit = Self(rawValue: "Limit")
        public static let market = Self(rawValue: "Market")
        public static let takeProfitMarket = Self(rawValue: "Take Profit Market")
        public static let stopMarket = Self(rawValue: "Stop Market")
    }
}

// MARK: - Wire

extension Hyperliquid.Order: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, side, limitPx, sz, oid, timestamp, cloid, orderType
    }

    /// The frontend form adds `orderType` and the other ``Details`` fields to the plain form.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        side = try container.decode(Hyperliquid.Side.self, forKey: .side)
        limitPrice = try container.decode(WireDecimal.self, forKey: .limitPx).value
        size = try container.decode(WireDecimal.self, forKey: .sz).value
        id = try container.decode(Hyperliquid.OrderID.self, forKey: .oid)
        time = try container.decode(WireDate.self, forKey: .timestamp).value
        clientID = try container.decodeIfPresent(Hyperliquid.ClientOrderID.self, forKey: .cloid)
        details = container.contains(.orderType) ? try Details(from: decoder) : nil
    }
}

extension Hyperliquid.Order.Details: Decodable {
    private enum CodingKeys: String, CodingKey {
        case orderType, origSz, tif, reduceOnly, isTrigger, triggerPx, triggerCondition, isPositionTpsl, children
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Hyperliquid.Order.Kind.self, forKey: .orderType)
        originalSize = try container.decode(WireDecimal.self, forKey: .origSz).value
        timeInForce = try container.decodeIfPresent(Hyperliquid.TimeInForce.self, forKey: .tif)
        reduceOnly = try container.decode(Bool.self, forKey: .reduceOnly)
        isTrigger = try container.decode(Bool.self, forKey: .isTrigger)
        triggerPrice = try container.decode(WireDecimal.self, forKey: .triggerPx).value
        triggerCondition = try container.decode(String.self, forKey: .triggerCondition)
        isPositionTakeProfitStopLoss = try container.decode(Bool.self, forKey: .isPositionTpsl)
        children = try container.decodeIfPresent([Hyperliquid.Order].self, forKey: .children) ?? []
    }
}
