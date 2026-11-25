import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Slippage")
    struct SlippageTests {
        @Test func `a percentage and its fraction are the same slippage`() {
            #expect(Hyperliquid.Slippage.percent(5) == .fraction(Decimal(string: "0.05")!))
            #expect(Hyperliquid.Slippage.percent(Decimal(string: "0.5")!).fraction == Decimal(string: "0.005")!)
        }
    }
}
