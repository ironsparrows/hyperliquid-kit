import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    @Suite(
        "Live streams", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and a valid HYPERLIQUID_ACCOUNT to run"),
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

        /// The first `count` elements of `stream`; fewer when it ends sooner.
        private static func take<Element>(_ count: Int, from stream: AsyncThrowingStream<Element, any Error>)
            async throws -> [Element]
        {
            var elements: [Element] = []
            for try await element in stream.prefix(count) { elements.append(element) }
            return elements
        }

        @Test func `BTC market streams decode a few values each`() async throws {
            let client = Hyperliquid.Client()
            let books = try await Self.take(2, from: client.stream.orderBook("BTC", precision: .significantFigures(.five)))
            #expect(books.count == 2 && books.allSatisfy { $0.coin == "BTC" })
            let best = try await Self.take(3, from: client.stream.bestBidOffer("BTC"))
            #expect(best.count == 3 && best.allSatisfy { $0.coin == "BTC" })
            let trades = try await Self.take(2, from: client.stream.trades("BTC"))
            #expect(trades.count == 2 && trades.joined().allSatisfy { $0.coin == "BTC" })
            let candles = try await Self.take(2, from: client.stream.candles("BTC", interval: .oneMinute))
            #expect(candles.count == 2 && candles.allSatisfy { $0.interval == .oneMinute })
            let contexts = try await Self.take(2, from: client.stream.assetContext("BTC"))
            #expect(contexts.count == 2 && contexts.allSatisfy { $0.markPrice > 0 })
            await client.stream.disconnect()
        }

        @Test func `compressed feeds decode a few values each`() async throws {
            let client = Hyperliquid.Client()
            let books = try await Self.take(3, from: client.stream.orderBookUpdates("BTC"))
            #expect(books.count == 3 && books.allSatisfy { $0.coin == "BTC" && !$0.bids.isEmpty && !$0.asks.isEmpty })
            let prices = try await Self.take(2, from: client.stream.prices())
            #expect(prices.count == 2 && prices.allSatisfy { $0["BTC"]?.markPrice != nil })
            let contexts = try await Self.take(2, from: client.stream.assetContexts())
            #expect(contexts.count == 2 && contexts.allSatisfy { $0["BTC"] != nil })
            await client.stream.disconnect()
        }
    }
}
