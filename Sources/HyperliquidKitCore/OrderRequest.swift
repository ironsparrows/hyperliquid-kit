public import Foundation

extension Hyperliquid {
    /// An order to place: a limit order or a trigger order, built with ``limit(_:_:price:size:timeInForce:reduceOnly:clientID:)``
    /// or ``trigger(_:_:_:triggerPrice:size:execution:reduceOnly:clientID:)``.
    ///
    /// Prices and sizes are sent as written, without trailing zeros. Hyperliquid rejects a price or size
    /// with more decimals than the perpetual allows; write them with `Decimal(string:)`, since a
    /// floating-point literal such as `0.1` isn't exact.
    public struct OrderRequest: Hashable, Sendable {
        public let side: Side
        public let coin: Coin
        /// The limit price: the worst price the order fills at.
        public let price: Decimal
        public let size: Decimal
        public let reduceOnly: Bool
        public let clientID: ClientOrderID?
        package let kind: Kind

        package enum Kind: Hashable, Sendable {
            case limit(TimeInForce)
            case trigger(TriggerKind, triggerPrice: Decimal, isMarket: Bool)
        }

        /// A limit order. A reduce-only order never increases a position.
        public static func limit(
            _ side: Side, _ coin: Coin, price: Decimal, size: Decimal, timeInForce: TimeInForce = .goodTilCanceled,
            reduceOnly: Bool = false, clientID: ClientOrderID? = nil
        ) -> Self {
            Self(
                side: side, coin: coin, price: price, size: size, reduceOnly: reduceOnly, clientID: clientID,
                kind: .limit(timeInForce)
            )
        }

        /// A take-profit or stop-loss order that is placed when the mark price reaches `triggerPrice`.
        ///
        /// Trigger orders are reduce-only by default: Hyperliquid rejects take-profit and stop-loss orders
        /// that aren't.
        public static func trigger(
            _ side: Side, _ coin: Coin, _ kind: TriggerKind, triggerPrice: Decimal, size: Decimal,
            execution: TriggerExecution, reduceOnly: Bool = true, clientID: ClientOrderID? = nil
        ) -> Self {
            let (price, isMarket) =
                switch execution {
                case .market(let limitPrice): (limitPrice, true)
                case .limit(let price): (price, false)
                }
            return Self(
                side: side, coin: coin, price: price, size: size, reduceOnly: reduceOnly, clientID: clientID,
                kind: .trigger(kind, triggerPrice: triggerPrice, isMarket: isMarket)
            )
        }
    }

    /// How the orders placed together relate: on their own, or as a parent order with take-profit and
    /// stop-loss orders.
    public struct Grouping: Hashable, Sendable {
        /// Hyperliquid's name for the grouping.
        package let name: String

        private init(name: String) {
            self.name = name
        }

        /// Each order stands on its own. Hyperliquid's `"na"`.
        public static let standalone = Self(name: "na")
        /// A parent order followed by take-profit and stop-loss orders for its size.
        public static let normalTakeProfitStopLoss = Self(name: "normalTpsl")
        /// Take-profit and stop-loss orders for the whole position, resized as the position changes.
        public static let positionTakeProfitStopLoss = Self(name: "positionTpsl")
    }

    /// What a trigger order places when it triggers.
    public enum TriggerExecution: Hashable, Sendable {
        /// A market order that fills no worse than `limitPrice`.
        case market(limitPrice: Decimal)
        /// A limit order at `price`.
        case limit(price: Decimal)
    }
}
