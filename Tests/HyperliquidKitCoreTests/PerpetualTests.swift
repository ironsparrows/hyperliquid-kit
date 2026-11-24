import Foundation
import Testing
@testable import HyperliquidKitCore

extension HyperliquidKitCoreTests {
    @Suite("Perpetual metadata")
    struct PerpetualTests {
        @Test func `the first perp DEX's meta decodes in asset-ID order with its margin tables`() throws {
            let perpetuals = try JSONDecoder().decode(PerpetualMetadata.self, from: Fixture.data("meta")).perpetuals
            let btc = try #require(perpetuals.first)
            #expect(btc.name == "BTC")
            #expect(btc.sizeDecimals == 5)
            #expect(btc.maxLeverage == 40)
            #expect(
                btc.marginTable
                    == .init(
                        description: "tiered 40x",
                        tiers: [.init(lowerBound: 0, maxLeverage: 40), .init(lowerBound: 150_000_000, maxLeverage: 20)]
                    )
            )
            #expect(btc.marginMode == nil)
            #expect(perpetuals.contains { $0.isDelisted })
            #expect(perpetuals.contains { $0.marginMode == .strictIsolated })
        }

        @Test func `a builder-deployed perp DEX's meta decodes with prefixed coins`() throws {
            let perpetuals = try JSONDecoder().decode(PerpetualMetadata.self, from: Fixture.data("meta_xyz")).perpetuals
            #expect(perpetuals.first?.name == "xyz:XYZ100")
            #expect(perpetuals.allSatisfy { $0.name.dex == .named("xyz") })
        }

        @Test func `every perp DEX's meta decodes`() throws {
            let metas = try JSONDecoder().decode([PerpetualMetadata].self, from: Fixture.data("allPerpMetas"))
            #expect(metas.first?.perpetuals.first?.name == "BTC")
            #expect(metas.count > 1)
        }

        @Test(arguments: [3, 10, 20, 49])
        func `a margin table ID under 50 is one tier at that leverage`(id: Int) throws {
            let table = try #require(Hyperliquid.MarginTable.resolving(id, in: [:]))
            #expect(table.tiers == [.init(lowerBound: 0, maxLeverage: id)])
        }

        @Test func `a margin table ID of 50 or more must be listed`() throws {
            #expect(Hyperliquid.MarginTable.resolving(56, in: [:]) == nil)
            let json = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":56}],"marginTables":[]}"#
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(PerpetualMetadata.self, from: Data(json.utf8))
            }
        }

        @Test func `a perpetual without a margin table ID has no table`() throws {
            let json = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":50}],"marginTables":[]}"#
            let perpetual = try JSONDecoder().decode(PerpetualMetadata.self, from: Data(json.utf8)).perpetuals.first
            #expect(perpetual?.marginTable == nil)
        }
    }
}
