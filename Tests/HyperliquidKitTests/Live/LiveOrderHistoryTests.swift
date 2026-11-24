import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    @Suite(
        "Live order history", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and a valid HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveOrderHistoryTests {
        private let client = Hyperliquid.Client(account: LiveTestSettings.values?.account)

        @Test func `the account's orders decode`() async throws {
            _ = try await client.order.pending()
            _ = try await client.order.pendingDetailed()
            let history = try await client.order.history()
            for historical in history.prefix(1) {
                #expect(try await client.order.status(.id(historical.order.id)) != nil)
            }
            #expect(try await client.order.status(.id(.init(rawValue: 1))) == nil)
        }

        @Test func `the account's fills decode`() async throws {
            _ = try await client.order.fills()
            _ = try await client.order.fills(from: Date.now.addingTimeInterval(-30 * 86_400), aggregateByTime: true)
        }

        @Test func `the account's TWAP slice fills and history decode`() async throws {
            _ = try await client.twap.sliceFills()
            _ = try await client.twap.history()
        }
    }
}
