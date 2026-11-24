import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    // Trades on mainnet with the account's API wallet: streams the account, buys about $11 of BTC with
    // a market order, then closes that size, and checks the pushes decode.
    @Suite(
        "Live account streams", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveAccountStreamTests {
        @Test func `account streams decode while a BTC position opens and closes`() async throws {
            let values = try #require(LiveTestSettings.values)
            let client = Hyperliquid.Client(
                account: values.account, signer: try Hyperliquid.PrivateKeySigner(hexKey: values.agentKey)
            )
            let stream = client.stream
            var orderUpdates = stream.orderUpdates().makeAsyncIterator()
            var events = stream.events().makeAsyncIterator()
            var fills = stream.fills().makeAsyncIterator()
            let notifications = Task { for try await _ in stream.notifications() {} }

            // Snapshots and state arrive on subscribing.
            #expect(try await fills.next()?.isSnapshot == true)
            #expect(try await stream.fundingPayments().first { _ in true }?.isSnapshot == true)
            #expect(try await stream.ledger().first { _ in true }?.isSnapshot == true)
            #expect(try await stream.twapSliceFills().first { _ in true }?.isSnapshot == true)
            #expect(try await stream.twapHistory().first { _ in true }?.isSnapshot == true)
            #expect(try await stream.perpetualState().first { _ in true } != nil)
            #expect(try await stream.pendingOrders().first { _ in true } != nil)
            #expect(try await stream.tradingLimits("BTC").first { _ in true }?.coin == "BTC")
            #expect(try await stream.balances().first { _ in true } != nil)
            #expect(try await stream.twapStates().first { _ in true } != nil)

            let mid = try #require(try await client.market.mids()["BTC"])
            let sizeDecimals = try #require(try await client.market.perpetuals().first { $0.name == "BTC" }).sizeDecimals
            var size = Decimal()
            var exact = Decimal(11) / mid
            NSDecimalRound(&size, &exact, sizeDecimals, .up)
            let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
            #expect(opened.first?.status == .filled, "\(opened)")
            let closed = try await client.order.close("BTC", size: size)
            #expect(closed.first?.status == .filled, "\(closed)")

            #expect(try await orderUpdates.next()?.order.coin == "BTC")
            #expect(try await events.next() != nil)
            let update = try #require(try await fills.next())
            #expect(!update.isSnapshot && update.elements.contains { $0.coin == "BTC" })
            notifications.cancel()
            await stream.disconnect()
        }
    }
}
