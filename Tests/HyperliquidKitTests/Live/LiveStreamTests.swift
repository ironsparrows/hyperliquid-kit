import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    @Suite(
        "Live streams", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveStreamTests {
        @Test func `mids stream on the first and a builder-deployed perp DEX`() async throws {
            let client = Hyperliquid.Client()
            let dex = try #require(try await client.market.perpDexs().first?.dex)
            var first = client.stream.mids().makeAsyncIterator()
            var builder = client.stream.mids(dex: dex).makeAsyncIterator()
            #expect(try await first.next()?["BTC"] != nil)
            #expect(try await builder.next()?.keys.allSatisfy { $0.dex == dex } == true)
            await client.stream.disconnect()
        }
    }
}
