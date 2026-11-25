import Foundation
import HyperliquidKit
import HyperliquidKitTestSupport
import Testing

extension HyperliquidKitTests.LiveTradingTests {
    // Places real orders on mainnet with the account's API wallet: resting BTC buys of $11 to $13 far
    // under the mid price, modified and canceled by client order ID and with take-profit and stop-loss
    // children; about $14 of BTC bought, given a take-profit and a stop-loss, and closed; a scheduled
    // cancel-all set and cleared, which Hyperliquid refuses until the account has traded enough; and a
    // nonce spent twice. Every order, child or trigger is worth at least $11 at its own price.
    @Suite(
        "Live order management", .tags(.live),
        .enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and a valid HYPERLIQUID_ACCOUNT to run"),
        .timeLimit(.minutes(2)), .serialized
    )
    struct LiveOrderManagementTests {
        private let client: Hyperliquid.Client

        init() throws {
            let values = try #require(LiveTestSettings.values)
            client = Hyperliquid.Client(
                account: values.account, signer: try Hyperliquid.PrivateKeySigner(hexKey: values.agentKey)
            )
        }

        private func price(times fraction: Decimal) async throws -> Decimal {
            try await HyperliquidKitTests.LiveTradingTests.btcPrice(times: fraction, on: client)
        }

        @Test func `a resting order is found, modified and canceled by its client order ID`() async throws {
            let clientID = Hyperliquid.ClientOrderID.random()
            let price = try await price(times: Decimal(string: "0.9")!)
            let size = try await HyperliquidKitTests.LiveTradingTests.btcSize(worth: 11, at: price, on: client)

            let placed = try await client.order.place([
                .limit(.buy, "BTC", price: price, size: size, timeInForce: .addLiquidityOnly, clientID: clientID)
            ])
            #expect(placed.first?.status == .resting, "\(placed)")
            #expect(try await client.order.status(.clientID(clientID))?.status == .open)

            let lower = try await self.price(times: Decimal(string: "0.89")!)
            let newClientID = Hyperliquid.ClientOrderID.random()
            let modified = try await client.order.modify([
                .init(
                    .clientID(clientID),
                    to: .limit(.buy, "BTC", price: lower, size: size, timeInForce: .addLiquidityOnly, clientID: newClientID))
            ])
            #expect(modified.first?.status == .resting, "\(modified)")

            // The modify replaced the order, so its first client ID is gone and Hyperliquid answers it with
            // a missing-order error. Canceling both also cancels the first order if the modify didn't.
            let canceled = try await client.order.cancel(clientIDs: [clientID, newClientID].map { .init($0, coin: "BTC") })
            #expect(canceled.map { $0.isCanceled } == [false, true], "\(canceled)")
        }

        @Test func `a take-profit and a stop-loss wait on their order and go with its cancel`() async throws {
            let price = try await price(times: Decimal(string: "0.9")!)
            let takeProfit = try await self.price(times: Decimal(string: "1.5")!)
            let stopLoss = try await self.price(times: Decimal(string: "0.8")!)
            let size = try await HyperliquidKitTests.LiveTradingTests.btcSize(worth: 11, at: stopLoss, on: client)
            let children = [Hyperliquid.ClientOrderID.random(), .random()]

            let placed = try await client.order.place(
                [
                    .limit(.buy, "BTC", price: price, size: size, timeInForce: .addLiquidityOnly),
                    .trigger(
                        .sell, "BTC", .takeProfit, triggerPrice: takeProfit, size: size, execution: .limit(price: takeProfit),
                        clientID: children[0]),
                    .trigger(
                        .sell, "BTC", .stopLoss, triggerPrice: stopLoss, size: size, execution: .limit(price: stopLoss),
                        clientID: children[1]),
                ],
                grouping: .normalTakeProfitStopLoss
            )
            #expect(placed.count == 3 && placed.allSatisfy { $0.status != .rejected }, "\(placed)")
            let parent = try #require(placed.first?.orderID, "\(placed)")
            let resting = try await client.order.pendingDetailed().first { $0.id == parent }
            #expect(resting?.details?.children.count == 2, "\(String(describing: resting))")
            let childIDs = resting?.details?.children.map(\.id) ?? []

            let canceled = try await client.order.cancel([.init(parent, coin: "BTC")])
            #expect(canceled.first?.isCanceled == true, "\(canceled)")
            let pending = try await client.order.pendingDetailed()
            #expect(
                !pending.contains {
                    $0.id == parent || childIDs.contains($0.id) || $0.clientID.map(children.contains) == true
                })
        }

        @Test func `a take-profit and a stop-loss rest on a position and are canceled before it closes`() async throws {
            // Prices are read before the buy, so only order calls stand between it and the close.
            let takeProfit = try await price(times: Decimal(string: "1.5")!)
            let takeProfitLimit = try await price(times: Decimal(string: "1.35")!)
            let stopLoss = try await price(times: Decimal(string: "0.8")!)
            let size = try await HyperliquidKitTests.LiveTradingTests.btcSize(worth: 11, at: stopLoss, on: client)
            let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
            let filled = try #require(opened.first?.filledSize, "\(opened)")

            let triggers = [Hyperliquid.ClientOrderID.random(), .random()]
            let placed = try await client.order.place(
                [
                    .trigger(
                        .sell, "BTC", .takeProfit, triggerPrice: takeProfit, size: filled, execution: .market(limitPrice: takeProfitLimit),
                        clientID: triggers[0]),
                    .trigger(
                        .sell, "BTC", .stopLoss, triggerPrice: stopLoss, size: filled, execution: .market(limitPrice: stopLoss),
                        clientID: triggers[1]),
                ],
                grouping: .positionTakeProfitStopLoss
            )
            #expect(placed.count == 2 && placed.allSatisfy { $0.status != .rejected }, "\(placed)")

            let canceled = try await client.order.cancel(clientIDs: triggers.map { .init($0, coin: "BTC") })
            #expect(canceled.allSatisfy { $0.isCanceled }, "\(canceled)")
            let closed = try await client.order.close("BTC", size: filled)
            #expect(closed.first?.status == .filled, "\(closed)")
        }

        /// Hyperliquid refuses a scheduled cancel until the account has traded enough volume
        /// ($1,000,000 when this was written). The refusal still shows the action arrived, signed for
        /// the account, so it is a known issue rather than a failure.
        @Test func `a scheduled cancel-all is set and cleared`() async throws {
            try await withKnownIssue(Self.volumeRefusal, isIntermittent: true) {
                try await client.order.scheduleCancelAll(at: .now.addingTimeInterval(60))
            } matching: {
                Self.isVolumeRefusal($0)
            }
            try await withKnownIssue(Self.volumeRefusal, isIntermittent: true) {
                try await client.order.clearScheduledCancel()
            } matching: {
                Self.isVolumeRefusal($0)
            }
        }

        private static let volumeRefusal: Comment = "Hyperliquid schedules a cancel only once the account has traded enough"

        private static func isVolumeRefusal(_ issue: Issue) -> Bool {
            (issue.error as? HyperliquidError)?.message?.contains("enough volume traded") == true
        }

        @Test func `a spent nonce can't be spent again`() async throws {
            let nonce = UInt64(Date.now.timeIntervalSince1970 * 1000) + 5_000
            try await client.order.invalidate(nonce: nonce)
            await #expect {
                try await client.order.invalidate(nonce: nonce)
            } throws: { error in
                (error as? HyperliquidError)?.kind == .actionRejected
            }
        }
    }
}
