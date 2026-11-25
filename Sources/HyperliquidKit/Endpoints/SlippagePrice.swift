import Foundation

/// The limit price of a market order: `price` moved by `slippage` against the order, rounded to 5
/// significant figures and then to `6 − sizeDecimals` decimals.
///
/// The arithmetic is done in `Double`, as Hyperliquid's own SDK does it, so a value halfway between two
/// ticks rounds the way the SDK rounds it, by its binary value.
func slippagePrice(_ price: Decimal, isBuy: Bool, slippage: Decimal, sizeDecimals: Int) -> Decimal {
    let fraction = Double(slippage.description)!
    let moved = Double(price.description)! * (isBuy ? 1 + fraction : 1 - fraction)
    let fiveFigures = Double(String(format: "%.5g", moved))!
    return Decimal(string: String(format: "%.*f", max(0, 6 - sizeDecimals), fiveFigures))!
}
