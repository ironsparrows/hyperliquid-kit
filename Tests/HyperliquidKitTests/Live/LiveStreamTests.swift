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

        @Test func `BTC market streams decode a few values each`() async throws {
            let client = Hyperliquid.Client()
            for try await book in client.stream.orderBook("BTC", precision: .significantFigures(.five)).prefix(2) {
                #expect(book.coin == "BTC")
            }
            for try await best in client.stream.bestBidOffer("BTC").prefix(3) {
                #expect(best.coin == "BTC")
            }
            for try await batch in client.stream.trades("BTC").prefix(2) {
                #expect(batch.allSatisfy { $0.coin == "BTC" })
            }
            for try await candle in client.stream.candles("BTC", interval: .oneMinute).prefix(2) {
                #expect(candle.interval == .oneMinute)
            }
            for try await context in client.stream.assetContext("BTC").prefix(2) {
                #expect(context.markPrice > 0)
            }
            await client.stream.disconnect()
        }

        @Test func `compressed feeds decode a few values each`() async throws {
            let client = Hyperliquid.Client()
            for try await book in client.stream.orderBookUpdates("BTC").prefix(3) {
                #expect(book.coin == "BTC" && !book.bids.isEmpty && !book.asks.isEmpty)
            }
            for try await prices in client.stream.prices().prefix(2) {
                #expect(prices["BTC"]?.markPrice != nil)
            }
            for try await contexts in client.stream.assetContexts().prefix(2) {
                #expect(contexts["BTC"] != nil)
            }
            await client.stream.disconnect()
        }
    }
}
