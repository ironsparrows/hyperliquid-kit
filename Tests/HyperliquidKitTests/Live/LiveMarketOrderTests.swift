import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests.LiveTradingTests {
    // Trades on mainnet with the account's API wallet: buys about $11 of BTC with a market order, then
    // closes that size with `order.close`.
    @Suite(
        "Live market orders", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveMarketOrderTests {
        @Test func `a BTC position opens with a market order and closes`() async throws {
            let values = try #require(LiveTestSettings.values)
            let client = Hyperliquid.Client(
                account: values.account, signer: try Hyperliquid.PrivateKeySigner(hexKey: values.agentKey)
            )
            let mid = try #require(try await client.market.mids()["BTC"])
            let sizeDecimals = try #require(try await client.market.perpetuals().first { $0.coin == "BTC" }).sizeDecimals
            var size = Decimal()
            var exact = Decimal(11) / mid
            NSDecimalRound(&size, &exact, sizeDecimals, .up)

            let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
            #expect(opened.first?.status == .filled, "\(opened)")
            #expect(try await client.account.perpetualState().positions.contains { $0.coin == "BTC" })

            let closed = try await client.order.close("BTC", size: size)
            #expect(closed.first?.status == .filled, "\(closed)")
        }
    }
}
