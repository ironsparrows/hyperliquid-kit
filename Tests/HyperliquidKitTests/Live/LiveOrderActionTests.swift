import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests.LiveTradingTests {
    // Places a real order on mainnet with the account's API wallet: a resting buy of about $11 of BTC
    // 10 % under the mid price, then modifies and cancels it.
    @Suite(
        "Live order actions", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and a valid HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveOrderActionTests {
        @Test func `a resting BTC order is placed, modified and canceled`() async throws {
            let values = try #require(LiveTestSettings.values)
            let client = Hyperliquid.Client(
                account: values.account, signer: try Hyperliquid.PrivateKeySigner(hexKey: values.agentKey)
            )
            let mid = try #require(try await client.market.mids()["BTC"])
            let price = Self.fiveSignificantFigures(mid * Decimal(string: "0.9")!)
            let size = try await HyperliquidKitTests.LiveTradingTests.btcSize(worth: 11, at: price, on: client)

            let placed = try await client.order.place([.limit(.buy, "BTC", price: price, size: size, timeInForce: .addLiquidityOnly)])
            let id = try #require(placed.first?.orderID, "\(placed)")
            #expect(placed.first?.status == .resting)
            #expect(try await client.order.pending().contains { $0.id == id })

            let lower = Self.fiveSignificantFigures(price * Decimal(string: "0.99")!)
            let modified = try await client.order.modify([
                .init(.id(id), to: .limit(.buy, "BTC", price: lower, size: size, timeInForce: .addLiquidityOnly))
            ])
            let newID = try #require(modified.first?.orderID, "\(modified)")

            let canceled = try await client.order.cancel([.init(newID, coin: "BTC")])
            #expect(canceled.first?.isCanceled == true, "\(canceled)")
        }

        private static func fiveSignificantFigures(_ value: Decimal) -> Decimal {
            let integerDigits = NSDecimalNumber(decimal: value).int64Value.description.count
            return rounded(value, scale: max(0, 5 - integerDigits), .plain)
        }

        private static func rounded(_ value: Decimal, scale: Int, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
            var value = value
            var result = Decimal()
            NSDecimalRound(&result, &value, scale, mode)
            return result
        }
    }
}
