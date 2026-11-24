import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests {
    @Suite(
        "Live account state", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2))
    )
    struct LiveAccountStateTests {
        private let client = Hyperliquid.Client(account: LiveTestSettings.values?.account)

        @Test func `the account's state, balances and mode decode`() async throws {
            _ = try await client.account.perpetualState()
            _ = try await client.account.balances()
            _ = try await client.account.mode()
        }

        @Test func `the account's fees, limits and related addresses decode`() async throws {
            _ = try await client.account.fees()
            _ = try await client.account.rateLimit()
            _ = try await client.account.role()
            _ = try await client.account.subAccounts()
            _ = try await client.account.apiWallets()
            _ = try await client.position.tradingLimits("BTC")
        }

        @Test func `the account's history decodes`() async throws {
            let monthAgo = Date.now.addingTimeInterval(-30 * 86_400)
            _ = try await client.account.portfolio()
            _ = try await client.account.ledger(from: monthAgo)
            _ = try await client.position.fundingPayments(from: monthAgo)
        }
    }
}
