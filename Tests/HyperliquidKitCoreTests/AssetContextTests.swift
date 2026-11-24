import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Asset context")
    struct AssetContextTests {
        @Test func `every recorded context decodes, BTC's with its exact values`() throws {
            let response = try JSONSerialization.jsonObject(with: Fixture.data("metaAndAssetCtxs")) as? [Any]
            let contextsJSON = try JSONSerialization.data(withJSONObject: try #require(response?.last))
            let contexts = try JSONDecoder().decode([Hyperliquid.AssetContext].self, from: contextsJSON)
            let btc = try #require(contexts.first)
            #expect(btc.markPrice == Decimal(string: "59687.0"))
            #expect(btc.midPrice == Decimal(string: "59686.5"))
            #expect(btc.funding == Decimal(string: "0.000000257"))
            #expect(btc.dayNotionalVolume == Decimal(string: "4632109169.5806188583"))
            #expect(btc.impactBidPrice == Decimal(string: "59686.0"))
            #expect(btc.impactAskPrice == Decimal(string: "59687.0"))
            #expect(contexts.contains { $0.midPrice == nil })
        }
    }
}
