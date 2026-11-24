import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Perp DEX details")
    struct PerpDexTests {
        @Test func `every builder-deployed perp DEX decodes after the first perp DEX's null`() throws {
            let dexes = try JSONDecoder().decode([Hyperliquid.PerpDex.Details?].self, from: Fixture.data("perpDexs"))
            #expect(dexes.first == .some(nil))
            let xyz = try #require(dexes.dropFirst().first ?? nil)
            #expect(xyz.dex == .named("xyz"))
            #expect(xyz.fullName == "XYZ")
            #expect(xyz.openInterestCaps["xyz:AAPL"] == Decimal(string: "200000000.0"))
            #expect(dexes.dropFirst().allSatisfy { $0 != nil })
        }
    }
}
