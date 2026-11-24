import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    // Trades on mainnet with the account's API wallet. Sets BTC to 10× isolated and back; opens about
    // $11 of BTC, adds and removes $1 of margin and tops it up to 5×, then closes that size; starts a
    // $110 BTC TWAP over 7 days and cancels it. A slice that filled before the cancel stays open.
    @Suite(
        "Live leverage, margin and TWAP actions", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run"),
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

        /// A BTC size worth about `dollars` at the mid price.
        private func size(worth dollars: Decimal) async throws -> Decimal {
            let mid = try #require(try await client.market.mids()["BTC"])
            let sizeDecimals = try #require(try await client.market.perpetuals().first { $0.name == "BTC" }).sizeDecimals
            var size = Decimal()
            var exact = dollars / mid
            NSDecimalRound(&size, &exact, sizeDecimals, .up)
            return size
        }

        @Test func `leverage changes and returns, and isolated margin moves on a small position`() async throws {
            let original = try await client.position.tradingLimits("BTC").leverage
            try await client.position.setLeverage(.isolated(10), for: "BTC")
            #expect(try await client.position.tradingLimits("BTC").leverage == .isolated(10))

            let size = try await size(worth: 11)
            let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
            #expect(opened.first?.status == .filled, "\(opened)")
            try await client.position.adjustMargin("BTC", by: 1)
            try await client.position.adjustMargin("BTC", by: -1)
            try await client.position.topUpMargin("BTC", toLeverage: 5)
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
