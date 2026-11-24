import Foundation
import HyperliquidKitCore

/// The number as an action writes it, with at most 8 decimals; more throw rather than round.
///
/// - Throws: `invalidRequest` naming `field` for more decimals, or for NaN, before anything is sent.
func wireNumber(_ value: Decimal, _ field: String) throws(Hyperliquid.ClientError) -> String {
    try checkedText(value, field, maxDecimals: 8)
}

/// A USD amount as an action's integer of millionths, such as `1000000` for 1 USD.
///
/// - Throws: `invalidRequest` naming `field` for more than 6 decimals, which the integer can't carry,
///   for an amount beyond the integer's range, or for NaN, before anything is sent.
func microdollars(_ amount: Decimal, _ field: String) throws(Hyperliquid.ClientError) -> Int64 {
    let text = try checkedText(amount, field, maxDecimals: 6)
    guard abs(amount) < 9_000_000_000_000 else {
        throw Hyperliquid.ClientError(.invalidRequest, message: "The \(field) \(text) is too large to send")
    }
    return NSDecimalNumber(decimal: amount * 1_000_000).int64Value
}

/// The number's wire text, after checking it is a number with at most `maxDecimals` decimals.
private func checkedText(_ value: Decimal, _ field: String, maxDecimals: Int) throws(Hyperliquid.ClientError) -> String {
    guard !value.isNaN else {
        throw Hyperliquid.ClientError(.invalidRequest, message: "The \(field) isn't a number")
    }
    let text = value.wireString
    let decimals = text.split(separator: ".").dropFirst().first?.count ?? 0
    guard decimals <= maxDecimals else {
        throw Hyperliquid.ClientError(
            .invalidRequest, message: "The \(field) \(text) has \(decimals) decimals; at most \(maxDecimals) can be sent"
        )
    }
    return text
}
