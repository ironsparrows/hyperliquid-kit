public import Foundation

extension Hyperliquid {
    /// An order to place: a limit order, a market order or a trigger order, built with
    /// ``limit(_:_:price:size:timeInForce:reduceOnly:clientID:)``, ``market(_:_:size:price:slippage:clientID:)``
    /// or ``trigger(_:_:_:triggerPrice:size:execution:reduceOnly:clientID:)``.
    ///
    /// Prices and sizes are sent as written, without trailing zeros; a market order's price is computed
    /// when it is placed. Hyperliquid rejects a price or size
    /// with more decimals than the perpetual allows; write them with `Decimal(string:)`, since a
    /// floating-point literal such as `0.1` isn't exact.
    public struct OrderRequest: Hashable, Sendable {
        public let side: Side
        public let coin: Coin
        /// The limit price: the worst price the order fills at, always set for limit and trigger orders.
        /// For a market order, the price its slippage applies to, or `nil` to use the mid price when the
        /// order is placed.
        public let price: Decimal?
        public let size: Decimal
        public let reduceOnly: Bool
        public let clientID: ClientOrderID?
        package let kind: Kind

        package enum Kind: Hashable, Sendable {
            case limit(TimeInForce)
            case market(Slippage)
            case trigger(TriggerKind, triggerPrice: Decimal, isMarket: Bool)
        }

        package init(
            side: Side, coin: Coin, price: Decimal?, size: Decimal, reduceOnly: Bool, clientID: ClientOrderID?, kind: Kind
        ) {
            self.side = side
            self.coin = coin
            self.price = price
            self.size = size
            self.reduceOnly = reduceOnly
            self.clientID = clientID
            self.kind = kind
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

        /// A market order: an immediate-or-cancel limit order at the mid price moved by `slippage` against
        /// the order, so by default a buy pays at most about the mid plus 5 %.
        ///
        /// The client reads the mid price of the coin's perp DEX when it places the order, unless `price`
        /// is given (a price of zero counts as none). Market orders can be placed, not used to modify an
        /// order. The limit price is rounded to 5 significant figures, then to `6 − sizeDecimals`
        /// decimals. Slippage is a worst-price cap, not an expected cost: on a thin book the order can
        /// fill far from the mid price. Negative slippage, or 100 % or more, throws
        /// ``ClientError/Reason/invalidRequest`` when the order is placed.
        public static func market(
            _ side: Side, _ coin: Coin, size: Decimal, price: Decimal? = nil, slippage: Slippage = .percent(5),
            clientID: ClientOrderID? = nil
        ) -> Self {
            Self(
                side: side, coin: coin, price: price, size: size, reduceOnly: false, clientID: clientID,
                kind: .market(slippage)
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
