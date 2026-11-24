import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    @Suite(
        "Live market data", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveMarketDataTests {
        private let market = Hyperliquid.Client().market

        @Test func `mids, the order book and recent trades decode`() async throws {
            #expect(try await market.mids()["BTC"] != nil)
            let book = try await market.orderBook("BTC", precision: .fiveSignificantFigures(mantissa: .two))
            #expect(!book.bids.isEmpty)
            #expect(!(try await market.recentTrades("BTC")).isEmpty)
        }

        @Test func `candles and funding history decode`() async throws {
            let now = Date.now
            let candles = try await market.candles("BTC", interval: .oneHour, from: now.addingTimeInterval(-6 * 3600), to: now)
            #expect(!candles.isEmpty)
            #expect(!(try await market.fundingHistory("BTC", from: now.addingTimeInterval(-6 * 3600))).isEmpty)
        }

        @Test func `funding predictions, limits and statuses decode`() async throws {
            _ = try await market.openInterestCapped()
            #expect(!(try await market.predictedFundings()).isEmpty)
            let dex = try #require(try await market.perpDexs().first?.dex)
            #expect(try await market.perpDexLimits(dex) != nil)
            _ = try await market.perpDexStatus(dex)
            _ = try await market.exchangeStatus()
        }

        @Test func `a builder-deployed perpetual's book decodes`() async throws {
            let dex = try #require(try await market.perpDexs().first?.dex)
            let coin = try #require(try await market.perpetuals(dex: dex).first?.name)
            #expect(try await market.orderBook(coin).coin == coin)
        }
    }
}
