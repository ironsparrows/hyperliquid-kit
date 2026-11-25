import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Slippage price")
    struct SlippagePriceTests {
        // Expected values from the Python SDK's `_slippage_price` formula,
        // `round(float(f"{px:.5g}"), 6 - szDecimals)`, run on the same inputs.
        @Test(arguments: [
            ("60243.5", true, "0.05", 5, "63256"),
            ("60243.5", false, "0.05", 5, "57231"),
            ("2014.35", true, "0.05", 4, "2115.1"),
            ("0.031452", false, "0.05", 0, "0.029879"),
            ("123456", true, "0.01", 5, "124690"),
            ("14.3161", true, "0.1", 1, "15.748"),
            ("0.000123456", true, "0.05", 0, "0.00013"),
            // Halfway cases, where the binary value decides the direction.
            ("58.53", false, "0.05", 1, "55.603"),
            ("73.55", true, "0", 5, "73.5"),
            ("3835000", true, "0.07", 3, "4103500"),
            ("0.011", false, "0.5", 3, "0.005"),
        ])
        func `the price moves by the slippage, then rounds to 5 significant figures and the perpetual's decimals`(
            price: String, isBuy: Bool, slippage: String, sizeDecimals: Int, expected: String
        ) {
            let result = slippagePrice(
                Decimal(string: price)!, isBuy: isBuy, slippage: Decimal(string: slippage)!, sizeDecimals: sizeDecimals
            )
            #expect(result.wireString == expected)
        }
    }
}
