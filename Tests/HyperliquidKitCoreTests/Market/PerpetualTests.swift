import Foundation
import HyperliquidKitTestSupport
import Testing

@testable import HyperliquidKitCore

extension HyperliquidKitCoreTests {
    @Suite("Perpetual metadata")
    struct PerpetualTests {
        @Test func `the first perp DEX's meta decodes in asset-ID order with its margin tables`() throws {
            let perpetuals = try JSONDecoder().decode(PerpetualMetadata.self, from: Fixture.data("meta", in: .market)).perpetuals
            let btc = try #require(perpetuals.first)
            #expect(btc.coin == "BTC")
            #expect(btc.sizeDecimals == 5)
            #expect(btc.maxLeverage == 40)
            #expect(
                btc.marginTable
                    == .init(
                        name: "tiered 40x",
                        tiers: [.init(lowerBound: 0, maxLeverage: 40), .init(lowerBound: 150_000_000, maxLeverage: 20)]
                    )
            )
            #expect(btc.marginMode == nil)
            #expect(perpetuals.contains { $0.isDelisted })
            #expect(perpetuals.contains { $0.marginMode == .strictIsolated })
        }

        @Test func `a builder-deployed perp DEX's meta decodes with prefixed coins`() throws {
            let perpetuals = try JSONDecoder().decode(PerpetualMetadata.self, from: Fixture.data("meta_xyz", in: .market)).perpetuals
            #expect(perpetuals.first?.coin == "xyz:XYZ100")
            #expect(perpetuals.allSatisfy { $0.coin.dex == .named("xyz") })
        }

        @Test func `every perp DEX's meta decodes`() throws {
            let metas = try JSONDecoder().decode([PerpetualMetadata].self, from: Fixture.data("allPerpMetas", in: .market))
            #expect(metas.first?.perpetuals.first?.coin == "BTC")
            #expect(metas.count > 1)
        }

        @Test func `a margin table Hyperliquid doesn't list leaves only its ID`() throws {
            let json = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":20}],"marginTables":[]}"#
            let perpetual = try #require(try JSONDecoder().decode(PerpetualMetadata.self, from: Data(json.utf8)).perpetuals.first)
            #expect(perpetual.marginTableID == 20)
            #expect(perpetual.marginTable == nil)
        }

        @Test func `a perpetual without a margin table ID has no table`() throws {
            let json = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":50}],"marginTables":[]}"#
            let perpetual = try JSONDecoder().decode(PerpetualMetadata.self, from: Data(json.utf8)).perpetuals.first
            #expect(perpetual?.marginTable == nil)
        }
    }
}
