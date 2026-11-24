import HyperliquidKitTestSupport
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite(
        "Live metadata", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and a valid HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveMetadataTests {
        private let market = Hyperliquid.Client().market

        @Test func `the first perp DEX's perpetuals and contexts decode`() async throws {
            let perpetuals = try await market.perpetuals()
            #expect(perpetuals.first?.coin == "BTC")
            let pairs = try await market.perpetualContexts()
            #expect(pairs.count == perpetuals.count)
        }

        @Test func `every perp DEX decodes, and its perpetuals resolve to asset IDs`() async throws {
            let dexes = try await market.perpDexs()
            let dex = try #require(dexes.first?.dex)
            let perpetuals = try await market.perpetuals(dex: dex)
            #expect(try await market.allPerpetuals().count >= perpetuals.count)
            let coin = try #require(perpetuals.first?.coin)
            let directory = AssetDirectory(info: InfoClient(network: .mainnet, transport: AsyncHTTPClientTransport(), timeout: nil))
            #expect(try await directory.asset(for: coin).id == 110_000)
            #expect(try await directory.asset(for: "BTC").id == 0)
        }
    }
}
