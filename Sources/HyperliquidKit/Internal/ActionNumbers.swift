import Foundation
import HyperliquidKitCore

/// The number as an action writes it: rounded to 8 decimals, as the Python SDK's `float_to_wire`
/// does, which throws when rounding would move it by 1e-12 or more.
///
/// - Throws: `invalidRequest` naming `field` for a number rounding would change, or for NaN, before
///   anything is sent.
func wireNumber(_ value: Decimal, _ field: String) throws(Hyperliquid.ClientError) -> String {
    let rounded = try rounded(value, field, decimals: 8, tolerance: Decimal(sign: .plus, exponent: -12, significand: 1))
    return rounded.wireString
}

/// A USD amount as an action's integer of millionths, such as `1000000` for 1 USD, as the Python
/// SDK's `float_to_usd_int` writes it: it throws when the millionths are 0.001 or more from a whole
/// number.
///
/// - Throws: `invalidRequest` naming `field` for an amount rounding would change, one beyond the
///   integer's range, or NaN, before anything is sent.
func microdollars(_ amount: Decimal, _ field: String) throws(Hyperliquid.ClientError) -> Int64 {
    let millionths = try rounded(
        amount * 1_000_000, field, decimals: 0, tolerance: Decimal(sign: .plus, exponent: -3, significand: 1)
    )
    guard let integer = Int64(millionths.wireString) else {
        throw Hyperliquid.ClientError(.invalidRequest, message: "The \(field) \(amount.wireString) is too large to send")
    }
    return integer
}

/// `value` rounded to `decimals`, half away from zero, after checking it is a number that rounding
/// moves by less than `tolerance`.
private func rounded(_ value: Decimal, _ field: String, decimals: Int, tolerance: Decimal)
    throws(Hyperliquid.ClientError) -> Decimal
{
    guard !value.isNaN else {
        throw Hyperliquid.ClientError(.invalidRequest, message: "The \(field) isn't a number")
    }
    var exact = value
    var result = Decimal()
    NSDecimalRound(&result, &exact, decimals, .plain)
    guard abs(result - value) < tolerance else {
        throw Hyperliquid.ClientError(
            .invalidRequest,
            message: "The \(field) \(value.wireString) has more than \(decimals) decimals; rounding would change it"
        )
    }
    return result
}
