import Foundation
import HyperliquidKitCore
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Asset context")
    struct AssetContextTests {
        @Test func `every recorded context decodes, BTC's with its exact values`() throws {
            let response = try JSONSerialization.jsonObject(with: Fixture.data("metaAndAssetCtxs", in: .market)) as? [Any]
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

        @Test(arguments: ["[]", #"["1.0"]"#, #"["1.0","2.0","3.0"]"#])
        func `impact prices other than a bid and an ask don't decode`(impactPrices: String) {
            let json = #"{"funding":"0","openInterest":"1","prevDayPx":"1","dayNtlVlm":"1","oraclePx":"1","markPx":"1","impactPxs":"# + impactPrices + "}"
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(Hyperliquid.AssetContext.self, from: Data(json.utf8))
            }
        }
    }
}
