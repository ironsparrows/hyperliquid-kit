import HyperliquidKitCore

/// A precision's parameters, as the `l2Book` request and the `l2Book` and `l2` subscriptions send them.
extension Hyperliquid.OrderBook.Precision {
    /// `nSigFigs`, and `mantissa` with it, as a book request or `l2Book` subscription takes them; none
    /// for full precision.
    var wireParameters: [ActionValue.Entry] {
        wireParameters(significantFigures: "nSigFigs", mantissa: "mantissa")
    }

    /// The significant figures, and the mantissa with them, under the names a request uses, such as
    /// `l2`'s `s` and `m`.
    func wireParameters(significantFigures figuresKey: String, mantissa mantissaKey: String) -> [ActionValue.Entry] {
        switch self {
        case .full:
            []
        case .significantFigures(let figures):
            [.init(key: figuresKey, value: .unsigned(UInt64(figures.rawValue)))]
        case .fiveSignificantFigures(let mantissa):
            [
                .init(key: figuresKey, value: .unsigned(5)),
                .init(key: mantissaKey, value: .unsigned(UInt64(mantissa.rawValue))),
            ]
        }
    }
}
