import Foundation
import HyperliquidKitCore

/// The number as an action writes it: rounded to 8 decimals, as the Python SDK's `float_to_wire`
/// does, which throws unless the rounding moves it by less than 1e-12 or leaves the same `Double`.
///
/// - Throws: `invalidRequest` naming `field` for a number rounding would change, or for NaN, before
///   anything is sent.
func wireNumber(_ value: Decimal, _ field: String) throws(Hyperliquid.ClientError) -> String {
    try rounded(value, field, decimals: 8, toleranceExponent: -12).wireString
}

/// A USD amount as an action's integer of millionths, such as `1000000` for 1 USD, as the Python
/// SDK's `float_to_usd_int` writes it: it throws unless the millionths are within 0.001 of a whole
/// number, or, as for every number, the same `Double` as their rounding.
///
/// - Throws: `invalidRequest` naming `field` for an amount rounding would change, one beyond the
///   integer's range, or NaN, before anything is sent.
func microdollars(_ amount: Decimal, _ field: String) throws(Hyperliquid.ClientError) -> Int64 {
    let millionths = try rounded(amount * 1_000_000, field, decimals: 0, toleranceExponent: -3)
    guard let integer = Int64(millionths.wireString) else {
        throw Hyperliquid.ClientError(.invalidRequest, message: "The \(field) \(amount.wireString) is too large to send")
    }
    return integer
}

/// `value` rounded to `decimals`, half away from zero, after checking that rounding moves it by less
/// than 10^`toleranceExponent`, either exactly or as the Python SDK compares, in `Double`. A
/// floating-point literal reaches `Decimal` through `Double`, carrying its binary error; for large
/// values, the `Double` comparison accepts a move of less than one `Double` step.
private func rounded(_ value: Decimal, _ field: String, decimals: Int, toleranceExponent: Int)
    throws(Hyperliquid.ClientError) -> Decimal
{
    let tolerance = Decimal(sign: .plus, exponent: toleranceExponent, significand: 1)
    guard !value.isNaN else {
        throw Hyperliquid.ClientError(.invalidRequest, message: "The \(field) isn't a number")
    }
    var exact = value
    var result = Decimal()
    NSDecimalRound(&result, &exact, decimals, .plain)
    // Through text, so each converts to the nearest `Double`, as Python's float parsing does.
    let move = abs(Double(result.wireString)! - Double(value.wireString)!)
    guard abs(result - value) < tolerance || move < Double(tolerance.wireString)! else {
        throw Hyperliquid.ClientError(
            .invalidRequest,
            message: "The \(field) \(value.wireString) has more than \(decimals) decimals; rounding would change it"
        )
    }
    return result
}
