import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Account stream pushes")
    struct AccountStreamTests {
        private let decoder = JSONDecoder()

        /// A field of the `data` of a recorded push `{"channel": …, "data": …}`, or the whole `data`, as JSON.
        private func payload(_ name: String, field: String? = nil) throws -> Data {
            let push = try #require(try JSONSerialization.jsonObject(with: Fixture.data(name)) as? [String: Any])
            var value = try #require(push["data"])
            if let field { value = try #require((value as? [String: Any])?[field]) }
            return try JSONSerialization.data(withJSONObject: value)
        }

        private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
            try decoder.decode(type, from: Data(json.utf8))
        }

        // MARK: Orders and fills

        @Test func `recorded order updates decode as orders with their statuses`() throws {
            let updates = try decoder.decode([Hyperliquid.HistoricalOrder].self, from: payload("ws_orderUpdates"))
            let update = try #require(updates.first)
            #expect(update.status == .open)
            #expect(update.order.coin == "VVV")
            #expect(update.order.id == .init(rawValue: 615_278_685_317))
            #expect(update.order.clientID == (try Hyperliquid.ClientOrderID("0x2ccd307b33ca3ff1b62a022c81ac1ed6")))
            #expect(update.order.details == nil)
            #expect(update.statusTime == Date(timeIntervalSince1970: 1_795_532_780.630))
        }

        @Test func `recorded fills decode, with a null TWAP ID`() throws {
            let fills = try decoder.decode([Hyperliquid.Fill].self, from: payload("ws_userFills", field: "fills"))
            let fill = try #require(fills.first)
            #expect(fill.coin == "VVV")
            #expect(fill.direction == .openLong)
            #expect(fill.isTaker)
            #expect(fill.twapID == nil)
            #expect(fill.tradeID == .init(rawValue: 294_364_579_493_482))
        }

        @Test func `recorded pending orders decode with how they were placed`() throws {
            let orders = try decoder.decode([Hyperliquid.Order].self, from: payload("ws_openOrders", field: "orders"))
            #expect(orders.count == 23)
            #expect(orders.allSatisfy { $0.details?.kind == .limit })
            #expect(orders.first?.details?.timeInForce == .addLiquidityOnly)
        }

        // MARK: State

        @Test func `a recorded perpetual state decodes its positions`() throws {
            let state = try decoder.decode(
                Hyperliquid.PerpetualState.self, from: payload("ws_clearinghouseState", field: "clearinghouseState")
            )
            #expect(state.positions.count == 31)
            let btc = try #require(state.positions.first)
            #expect(btc.coin == "BTC")
            #expect(btc.size == Decimal(string: "-0.60877"))
            #expect(btc.leverage == .cross(3))
            #expect(btc.cumulativeFunding?.allTime == Decimal(string: "-21937.658026"))
            #expect(state.time != nil)
        }

        @Test func `recorded trading limits and balances decode`() throws {
            let limits = try decoder.decode(Hyperliquid.TradingLimits.self, from: payload("ws_activeAssetData"))
            #expect(limits.coin == "BTC")
            #expect(limits.leverage == .cross(3))
            #expect(limits.maxTradeSizes == [Decimal(string: "75.25156")!, Decimal(string: "75.20254")!])
            #expect(limits.markPrice == Decimal(59886))
            let balances = try decoder.decode(SpotState.self, from: payload("ws_spotState", field: "spotState")).balances
            #expect(balances.map(\.token) == ["USDC", "HYPE"])
            #expect(balances.first?.total == Decimal(string: "5554.242992"))
        }

        // MARK: Snapshots

        @Test func `recorded funding payments decode without a hash`() throws {
            let payments = try decoder.decode(
                [Hyperliquid.FundingPayment].self, from: payload("ws_userFundings", field: "fundings")
            )
            #expect(payments.count == 100)
            let first = try #require(payments.first)
            #expect(first.coin == "INIT")
            #expect(first.hash == nil)
            #expect(first.usdc == Decimal(string: "-2.698481"))
            #expect(first.positionSize == Decimal(-68817))
            #expect(first.rate == Decimal(string: "-0.0004767758"))
            #expect(first.sampleCount == nil)
        }

        @Test func `recorded TWAP slice fills and history decode`() throws {
            let fills = try decoder.decode(
                [Hyperliquid.TwapSliceFill].self, from: payload("ws_userTwapSliceFills", field: "twapSliceFills")
            )
            #expect(fills.count == 30)
            #expect(fills.allSatisfy { $0.twapID == .init(rawValue: 2_814_131) && $0.fill.coin == "@107" })
            let history = try decoder.decode(
                [Hyperliquid.TwapHistoryEntry].self, from: payload("ws_userTwapHistory", field: "history")
            )
            #expect(history.map(\.status) == [.activated, .finished, .activated, .finished])
            #expect(history.first?.twap.duration == .seconds(300))
        }

        // MARK: Events

        @Test func `recorded fill and cancel events decode`() throws {
            let fills = try decoder.decode(Hyperliquid.UserEvent.self, from: payload("ws_user_fills"))
            guard case .fills(let list) = fills else {
                Issue.record("Expected fills, got \(fills)")
                return
            }
            #expect(list.first?.coin == "VVV")
            let cancel = try decoder.decode(Hyperliquid.UserEvent.self, from: payload("ws_user_nonUserCancel"))
            #expect(cancel == .nonUserCancel([.init(.init(rawValue: 615_277_885_225), coin: "ETH")]))
        }

        @Test func `funding and liquidation events decode as the subscriptions page types them`() throws {
            let funding = try decode(
                Hyperliquid.UserEvent.self,
                #"{"funding":{"time":1795521600020,"coin":"BTC","usdc":"0.634982","szi":"-0.60877","fundingRate":"0.0000125"}}"#
            )
            #expect(funding == .funding(.init(
                time: Date(timeIntervalSince1970: 1_795_521_600.020), hash: nil, coin: "BTC",
                usdc: Decimal(string: "0.634982")!, positionSize: Decimal(string: "-0.60877")!,
                rate: Decimal(string: "0.0000125")!
            )))
            let liquidation = try decode(
                Hyperliquid.UserEvent.self,
                #"{"liquidation":{"lid":7,"liquidator":"0x0000000000000000000000000000000000000001","liquidated_user":"0x0000000000000000000000000000000000000002","liquidated_ntl_pos":"1000.5","liquidated_account_value":"20.25"}}"#
            )
            #expect(liquidation == .liquidation(.init(
                id: .init(rawValue: 7), liquidator: "0x0000000000000000000000000000000000000001",
                liquidatedUser: "0x0000000000000000000000000000000000000002", positionNotional: Decimal(string: "1000.5")!,
                accountValue: Decimal(string: "20.25")!
            )))
        }

        @Test func `an event of an unknown kind keeps its name without reading its contents`() throws {
            #expect(try decode(Hyperliquid.UserEvent.self, #"{"somethingNew":{"x":1}}"#) == .unknown(kind: "somethingNew"))
        }

        @Test(arguments: ["{}", "[]", #"{"fills":{}}"#, #"{"fills":null}"#, #"{"fills":[],"x":1}"#, #"{"b":1,"a":2}"#])
        func `one event doesn't read from anything but an object with one readable field`(json: String) {
            #expect(throws: DecodingError.self) {
                try decode(Hyperliquid.UserEvent.self, json)
            }
        }

        // MARK: Batches

        @Test func `batches compare by snapshot flag and elements`() {
            let snapshot = Hyperliquid.Batch(isSnapshot: true, elements: [1, 2])
            #expect(snapshot == .init(isSnapshot: true, elements: [1, 2]))
            #expect(snapshot != .init(isSnapshot: false, elements: [1, 2]))
        }
    }
}
