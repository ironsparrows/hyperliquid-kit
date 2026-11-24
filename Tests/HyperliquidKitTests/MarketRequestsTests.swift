import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Market requests")
    struct MarketRequestsTests {
        private static let btcMeta = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":40}],"marginTables":[],"collateralToken":0}"#
        private static let xyzMeta = #"{"universe":[{"name":"xyz:XYZ100","szDecimals":4,"maxLeverage":30,"marginTableId":30}],"marginTables":[],"collateralToken":0}"#
        private static let context = #"{"funding":"0.0000125","openInterest":"688.11","prevDayPx":"15.322","dayNtlVlm":"1169046.29406","premium":null,"oraclePx":"14.32","markPx":"14.3161","midPx":null,"impactPxs":null,"dayBaseVlm":"81000.5"}"#

        @Test func `perpetuals read the perp DEX's meta`() async throws {
            let transport = FakeTransport(json: Self.btcMeta)
            let perpetuals = try await MarketRequests(info: .test(transport)).perpetuals()
            #expect(perpetuals.map(\.name) == ["BTC"])
            #expect(await transport.bodies == [#"{"type":"meta","dex":""}"#])
        }

        @Test func `each perpetual is paired with the context in the same position`() async throws {
            let transport = FakeTransport(json: "[" + Self.btcMeta + ",[" + Self.context + "]]")
            let pairs = try await MarketRequests(info: .test(transport)).perpetualContexts(dex: .named("xyz"))
            #expect(pairs.count == 1)
            #expect(pairs.first?.perpetual.name == "BTC")
            #expect(pairs.first?.context.markPrice == Decimal(string: "14.3161"))
            #expect(pairs.first?.context.impactBidPrice == nil)
            #expect(await transport.bodies == [#"{"type":"metaAndAssetCtxs","dex":"xyz"}"#])
        }

        @Test func `a context count that doesn't match the perpetuals throws an unexpected response`() async {
            let transport = FakeTransport(json: "[" + Self.btcMeta + ",[]]")
            await #expect {
                try await MarketRequests(info: .test(transport)).perpetualContexts()
            } throws: { error in
                (error as? HyperliquidError)?.kind == .unexpectedResponse
            }
        }

        @Test func `all perpetuals flatten every perp DEX's meta in order`() async throws {
            let transport = FakeTransport(json: "[" + Self.btcMeta + "," + Self.xyzMeta + "]")
            let perpetuals = try await MarketRequests(info: .test(transport)).allPerpetuals()
            #expect(perpetuals.map(\.name) == ["BTC", "xyz:XYZ100"])
            #expect(await transport.bodies == [#"{"type":"allPerpMetas"}"#])
        }

        @Test func `perp DEXs leave out the first perp DEX's null`() async throws {
            let transport = FakeTransport(
                json: #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888","oracleUpdater":null,"feeRecipient":null,"assetToStreamingOiCap":[["xyz:XYZ100","25000000.0"]]}]"#
            )
            let dexes = try await MarketRequests(info: .test(transport)).perpDexs()
            #expect(dexes.map(\.dex) == [.named("xyz")])
            #expect(dexes.first?.fundingMultipliers.isEmpty == true)
            #expect(await transport.bodies == [#"{"type":"perpDexs"}"#])
        }
    }
}
