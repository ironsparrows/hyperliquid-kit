import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests.LiveTradingTests {
    // Trades on mainnet with the account's API wallet. Sets BTC to 10× isolated and back; opens about
    // $11 of BTC, adds $2 of margin and removes $1, so it stays above what 10× needs, then closes that
    // size; starts a $110 BTC TWAP over 7 days and cancels it. A slice that filled before the cancel
    // stays open. Topping up to a target leverage is for isolated-only markets, so BTC doesn't take it.
    @Suite(
        "Live leverage, margin and TWAP actions", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and a valid HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2)), .serialized
    )
    struct LivePositionActionTests {
        private let client: Hyperliquid.Client

        init() throws {
            let values = try #require(LiveTestSettings.values)
            client = Hyperliquid.Client(
                account: values.account, signer: try Hyperliquid.PrivateKeySigner(hexKey: values.agentKey)
            )
        }

        private func size(worth dollars: Decimal) async throws -> Decimal {
            try await HyperliquidKitTests.LiveTradingTests.btcSize(worth: dollars, on: client)
        }

        @Test func `leverage changes and returns, and isolated margin moves on a small position`() async throws {
            let original = try await client.position.tradingLimits("BTC").leverage
            try await client.position.setLeverage(.isolated(10), for: "BTC")
            #expect(try await client.position.tradingLimits("BTC").leverage == .isolated(10))

            let size = try await size(worth: 11)
            let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
            #expect(opened.first?.status == .filled, "\(opened)")
            // About $1.10 backs $11 at 10×; Hyperliquid refuses a removal that leaves only that.
            try await client.position.adjustMargin("BTC", by: 2)
            try await client.position.adjustMargin("BTC", by: -1)
            let closed = try await client.order.close("BTC", size: size)
            #expect(closed.first?.status == .filled, "\(closed)")

            try await client.position.setLeverage(original, for: "BTC")
            #expect(try await client.position.tradingLimits("BTC").leverage == original)
        }

        @Test func `a TWAP starts and is canceled`() async throws {
            let size = try await size(worth: 110)
            let placed = try await client.twap.place(.init(.buy, "BTC", size: size, duration: .seconds(7 * 86_400)))
            let id = try #require(placed.twapID, "\(placed)")
            let canceled = try await client.twap.cancel(id, coin: "BTC")
            #expect(canceled.isCanceled, "\(canceled)")
            _ = try await client.twap.history()
            _ = try await client.twap.sliceFills()
        }
    }
}
