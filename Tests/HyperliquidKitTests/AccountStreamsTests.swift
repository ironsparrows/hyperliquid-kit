import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Account streams", .timeLimit(.minutes(1)))
    struct AccountStreamsTests {
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5},{"name":"ETH","szDecimals":4}]}"#
        private static let perpDexs = #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#
        private static let account: Hyperliquid.Address = "0x0000000000000000000000000000000000000001"
        private static let other: Hyperliquid.Address = "0x00000000000000000000000000000000000000a2"

        /// Streams whose coin or perp DEX check reads `listing`.
        private static func streams(
            _ transport: FakeWebSocketTransport, account: Hyperliquid.Address? = Self.account, listing: String = Self.meta
        ) -> (Streams, StreamConnection) {
            let connection = StreamConnection(
                url: URL(string: "wss://example.invalid/ws")!, transport: transport,
                directory: AssetDirectory(info: .test(FakeTransport(json: listing)))
            )
            return (Streams(connection: connection, account: account), connection)
        }

        private static func fill(_ tid: Int) -> String {
            #"{"coin":"BTC","px":"60000.0","sz":"0.001","side":"B","time":1795532765795,"startPosition":"0.0","dir":"Open Long","closedPnl":"0.0","hash":"0x0000000000000000000000000000000000000000000000000000000000000100","oid":615278381431,"crossed":true,"fee":"0.03","tid":\#(tid),"feeToken":"USDC","twapId":null}"#
        }

        private static func fills(_ user: Hyperliquid.Address, snapshot: Bool = false, tids: [Int]) -> String {
            let flag = snapshot ? #""isSnapshot":true,"# : ""
            return #"{"channel":"userFills","data":{\#(flag)"user":"\#(user)","fills":[\#(tids.map(fill).joined(separator: ","))]}}"#
        }

        // MARK: Subscriptions

        @Test func `each stream sends its subscription for the client's account as the subscriptions page writes it`()
            async throws
        {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let readers = [
                Task { for try await _ in streams.orderUpdates() {} },
                Task { for try await _ in streams.fills() {} },
                Task { for try await _ in streams.events() {} },
                Task { for try await _ in streams.fundingPayments() {} },
                Task { for try await _ in streams.ledger() {} },
                Task { for try await _ in streams.perpetualState() {} },
                Task { for try await _ in streams.pendingOrders() {} },
                Task { for try await _ in streams.tradingLimits("BTC") {} },
                Task { for try await _ in streams.balances() {} },
                Task { for try await _ in streams.notifications() {} },
                Task { for try await _ in streams.twapStates() {} },
                Task { for try await _ in streams.twapSliceFills() {} },
                Task { for try await _ in streams.twapHistory() {} },
            ]
            let session = try await transport.session()
            let sent = Set(try await session.sent(atLeast: 13))
            let user = #""user":"0x0000000000000000000000000000000000000001""#
            #expect(sent == [
                #"{"method":"subscribe","subscription":{"type":"orderUpdates",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"userFills",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"userEvents",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"userFundings",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"userNonFundingLedgerUpdates",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"clearinghouseState",\#(user),"dex":""}}"#,
                #"{"method":"subscribe","subscription":{"type":"openOrders",\#(user),"dex":""}}"#,
                #"{"method":"subscribe","subscription":{"type":"activeAssetData",\#(user),"coin":"BTC"}}"#,
                #"{"method":"subscribe","subscription":{"type":"spotState",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"notification",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"twapStates",\#(user),"dex":""}}"#,
                #"{"method":"subscribe","subscription":{"type":"userTwapSliceFills",\#(user)}}"#,
                #"{"method":"subscribe","subscription":{"type":"userTwapHistory",\#(user)}}"#,
            ])
            for reader in readers { reader.cancel() }
            await connection.disconnect()
        }

        @Test func `a given user wins over the client's account, and aggregated fills say so`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport, listing: Self.perpDexs)
            let readers = [
                Task { for try await _ in streams.fills(aggregateByTime: true, for: Self.other) {} },
                Task { for try await _ in streams.perpetualState(dex: .named("xyz"), for: Self.other) {} },
            ]
            let session = try await transport.session()
            let sent = Set(try await session.sent(atLeast: 2))
            #expect(sent == [
                #"{"method":"subscribe","subscription":{"type":"userFills","user":"0x00000000000000000000000000000000000000a2","aggregateByTime":true}}"#,
                #"{"method":"subscribe","subscription":{"type":"clearinghouseState","user":"0x00000000000000000000000000000000000000a2","dex":"xyz"}}"#,
            ])
            for reader in readers { reader.cancel() }
            await connection.disconnect()
        }

        @Test func `an account stream without an account ends with missingAccount before connecting`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, _) = Self.streams(transport, account: nil)
            await #expect {
                for try await _ in streams.fills() {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .missingAccount
            }
            #expect(await transport.sessions.isEmpty)
        }

        @Test func `trading limits of a spot coin are refused without a connection`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, _) = Self.streams(transport)
            await #expect {
                for try await _ in streams.tradingLimits("@107") {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
            }
            #expect(await transport.sessions.isEmpty)
        }

        /// The streams whose pushes carry no user.
        enum UserlessStream: CaseIterable, Sendable {
            case orderUpdates, events, notifications
        }

        private static func read(_ stream: UserlessStream, _ streams: Streams, for user: Hyperliquid.Address?)
            async throws
        {
            switch stream {
            case .orderUpdates: for try await _ in streams.orderUpdates(for: user) {}
            case .events: for try await _ in streams.events(for: user) {}
            case .notifications: for try await _ in streams.notifications(for: user) {}
            }
        }

        @Test(arguments: UserlessStream.allCases)
        func `a second account on a channel whose pushes carry no user is refused, the same account shares it`(
            stream: UserlessStream
        ) async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let first = Task { try await Self.read(stream, streams, for: nil) }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await #expect {
                try await Self.read(stream, streams, for: Self.other)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            let shared = Task { try await Self.read(stream, streams, for: Self.account) }
            try await eventually {
                let state = await connection.bookkeeping
                return state.consumers == 2 && state.subscribedTopics == 1 ? true : nil
            }
            #expect(await session.sent.count == 1)
            first.cancel()
            shared.cancel()
            await connection.disconnect()
        }

        @Test func `fills already streaming with the other aggregation are refused`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let plain = Task { for try await _ in streams.fills() {} }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await #expect {
                for try await _ in streams.fills(aggregateByTime: true) {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            plain.cancel()
            await connection.disconnect()
        }

        // MARK: Routing and snapshots

        @Test func `fills reach their user's stream as batches, the snapshot marked`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var mine = streams.fills().makeAsyncIterator()
            var theirs = streams.fills(for: Self.other).makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.push(Self.fills(Self.other, snapshot: true, tids: [9]))
            await session.push(Self.fills(Self.account, snapshot: true, tids: [1, 2]))
            await session.push(Self.fills(Self.account, tids: [3]))
            let snapshot = try #require(try await mine.next())
            #expect(snapshot.isSnapshot)
            #expect(snapshot.elements.compactMap(\.tradeID?.rawValue) == [1, 2])
            let update = try #require(try await mine.next())
            #expect(!update.isSnapshot)
            #expect(update.elements.compactMap(\.tradeID?.rawValue) == [3])
            #expect(try await theirs.next()?.elements.compactMap(\.tradeID?.rawValue) == [9])
            await connection.disconnect()
        }

        @Test func `a fills stream that joins a streaming subscription starts with the next new fills`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var first = streams.fills().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(Self.fills(Self.account, snapshot: true, tids: [1]))
            #expect(try await first.next()?.isSnapshot == true)
            var joined = streams.fills().makeAsyncIterator()
            try await eventually { await connection.bookkeeping.consumers == 2 ? true : nil }
            await session.push(Self.fills(Self.account, tids: [2]))
            let next = try #require(try await joined.next())
            #expect(!next.isSnapshot && next.elements.compactMap(\.tradeID?.rawValue) == [2])
            #expect(await session.sent.count == 1)
            await connection.disconnect()
        }

        @Test(arguments: [true, false])
        func `the client streams its vault, else its account, by default`(hasVault: Bool) async throws {
            let transport = FakeWebSocketTransport()
            let vault: Hyperliquid.Address = "0x00000000000000000000000000000000000000b3"
            let client = Hyperliquid.Client(
                account: Self.account, configuration: .init(vaultAddress: hasVault ? vault : nil),
                transport: FakeTransport(), webSocketTransport: transport
            )
            let reader = Task { for try await _ in client.stream.balances() {} }
            let session = try await transport.session()
            let expected = hasVault ? vault : Self.account
            #expect(try await session.sent(atLeast: 1) == [
                #"{"method":"subscribe","subscription":{"type":"spotState","user":"\#(expected)"}}"#
            ])
            reader.cancel()
            await client.stream.disconnect()
        }

        @Test func `funding, ledger and TWAP batches read their own lists`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var fundings = streams.fundingPayments().makeAsyncIterator()
            var ledger = streams.ledger().makeAsyncIterator()
            var slices = streams.twapSliceFills().makeAsyncIterator()
            var history = streams.twapHistory().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 4)
            let user = Self.account.description
            await session.push(
                #"{"channel":"userFundings","data":{"isSnapshot":true,"user":"\#(user)","fundings":[{"time":1795521600020,"coin":"BTC","usdc":"-2.5","szi":"1.0","fundingRate":"0.0000125","nSamples":null}]}}"#
            )
            await session.push(
                #"{"channel":"userNonFundingLedgerUpdates","data":{"isSnapshot":true,"user":"\#(user)","nonFundingLedgerUpdates":[{"time":1771691542187,"hash":"0x0000000000000000000000000000000000000000000000000000000000000101","delta":{"type":"deposit","usdc":"100.0"}}]}}"#
            )
            await session.push(
                #"{"channel":"userTwapSliceFills","data":{"user":"\#(user)","twapSliceFills":[{"fill":\#(Self.fill(5)),"twapId":2814131}]}}"#
            )
            await session.push(
                #"{"channel":"userTwapHistory","data":{"isSnapshot":true,"user":"\#(user)","history":[]}}"#
            )
            #expect(try await fundings.next()?.elements.first?.usdc == Decimal(string: "-2.5"))
            let update = try #require(try await ledger.next()?.elements.first)
            #expect(update.kind == .deposit && update.usdc == 100)
            let slice = try #require(try await slices.next())
            #expect(!slice.isSnapshot && slice.elements.first?.twapID == .init(rawValue: 2_814_131))
            #expect(try await history.next() == .init(isSnapshot: true, elements: []))
            await connection.disconnect()
        }

        @Test func `order updates arrive one by one, every update kept in order`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var updates = streams.orderUpdates().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            func update(_ oid: Int, _ status: String) -> String {
                #"{"order":{"coin":"VVV","side":"B","limitPx":"25.199","sz":"25.56","oid":\#(oid),"timestamp":1795532780630,"origSz":"25.56","cloid":"0x2ccd307b33ca3ff1b62a022c81ac1ed6"},"status":"\#(status)","statusTimestamp":1795532780630}"#
            }
            await session.push(#"{"channel":"orderUpdates","data":[\#(update(1, "open")),\#(update(1, "filled"))]}"#)
            await session.push(#"{"channel":"orderUpdates","data":[]}"#)
            await session.push(#"{"channel":"orderUpdates","data":[\#(update(2, "badAloPxRejected"))]}"#)
            var read: [String] = []
            while read.count < 3, let next = try await updates.next() { read.append("\(next.order.id) \(next.status.rawValue)") }
            #expect(read == ["1 open", "1 filled", "2 badAloPxRejected"])
            await connection.disconnect()
        }

        @Test func `events read fills and cancels, and name a kind they don't model`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var events = streams.events().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(#"{"channel":"user","data":{"somethingNew":{"x":1}}}"#)
            await session.push(#"{"channel":"user","data":{"fills":[\#(Self.fill(7))]}}"#)
            await session.push(#"{"channel":"user","data":{"nonUserCancel":[{"coin":"ETH","oid":615277885225}]}}"#)
            #expect(try await events.next() == .unknown(kind: "somethingNew"))
            guard case .fills(let fills) = try await events.next() else {
                Issue.record("Expected fills after the unknown event")
                return
            }
            #expect(fills.first?.tradeID == .init(rawValue: 7))
            #expect(try await events.next() == .nonUserCancel([.init(.init(rawValue: 615_277_885_225), coin: "ETH")]))
            await session.push(#"{"channel":"user","data":{"zeta":1,"nonUserCancel":[],"alpha":2}}"#)
            #expect(try await events.next() == .nonUserCancel([]))
            #expect(try await events.next() == .unknown(kind: "alpha"))
            #expect(try await events.next() == .unknown(kind: "zeta"))
            await session.push(#"{"channel":"user","data":{"fills":{}}}"#)
            await #expect(throws: DecodingError.self) { _ = try await events.next() }
            await connection.disconnect()
        }

        @Test func `state pushes and notifications read through their streams`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var state = streams.perpetualState().makeAsyncIterator()
            var pending = streams.pendingOrders().makeAsyncIterator()
            var limits = streams.tradingLimits("BTC").makeAsyncIterator()
            var balances = streams.balances().makeAsyncIterator()
            var notifications = streams.notifications().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 5)
            let user = Self.account.description
            await session.push(
                #"{"channel":"clearinghouseState","data":{"dex":"","user":"\#(user)","clearinghouseState":{"marginSummary":{"accountValue":"565.136441","totalNtlPos":"0.0","totalRawUsd":"565.136441","totalMarginUsed":"0.0"},"crossMarginSummary":{"accountValue":"565.136441","totalNtlPos":"0.0","totalRawUsd":"565.136441","totalMarginUsed":"0.0"},"crossMaintenanceMarginUsed":"0.0","withdrawable":"565.136441","assetPositions":[],"time":1795507735895}}}"#
            )
            await session.push(
                #"{"channel":"openOrders","data":{"dex":"","user":"\#(user)","orders":[{"coin":"VVV","side":"A","limitPx":"25.285","sz":"27.73","oid":615278345965,"timestamp":1795532764385,"triggerCondition":"N/A","isTrigger":false,"triggerPx":"0.0","children":[],"isPositionTpsl":false,"reduceOnly":false,"orderType":"Limit","origSz":"27.73","tif":"Alo","cloid":"0xacb002604faa6c540400000000000000"}]}}"#
            )
            await session.push(
                #"{"channel":"activeAssetData","data":{"user":"\#(user)","coin":"BTC","leverage":{"type":"cross","value":3},"maxTradeSzs":["75.25156","75.20254"],"availableToTrade":["1502171.64072","1501193.10348"],"markPx":"59886.0"}}"#
            )
            await session.push(
                #"{"channel":"spotState","data":{"user":"\#(user)","spotState":{"balances":[{"coin":"USDC","token":0,"total":"5554.242992","hold":"0.0","entryNtl":"0.0"}]}}}"#
            )
            await session.push(#"{"channel":"notification","data":{"notification":"Resting order filled: Sold 6.7 HYPE at $61.819"}}"#)
            #expect(try await state.next()?.withdrawable == Decimal(string: "565.136441"))
            #expect(try await pending.next()?.first?.details?.originalSize == Decimal(string: "27.73"))
            #expect(try await limits.next()?.leverage == .cross(3))
            #expect(try await balances.next()?.first?.token == "USDC")
            #expect(try await notifications.next() == "Resting order filled: Sold 6.7 HYPE at $61.819")
            await connection.disconnect()
        }

        @Test func `TWAP states read as a map by ID`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var states = streams.twapStates().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            let user = Self.account.description
            await session.push(
                #"{"channel":"twapStates","data":{"dex":"","user":"\#(user)","states":[[2814131,{"coin":"BTC","user":"\#(user)","side":"B","sz":"0.5","executedSz":"0.1","executedNtl":"6000.0","minutes":30,"reduceOnly":false,"randomize":true,"timestamp":1795486476950}]]}}"#
            )
            let running = try #require(try await states.next())
            #expect(running.keys.map(\.rawValue) == [2_814_131])
            #expect(running.values.first?.duration == .seconds(1800))
            await connection.disconnect()
        }

        @Test(arguments: [
            (#"{"channel":"orderUpdates","data":[]}"#, "orderUpdates", ""),
            (#"{"channel":"user","data":{"fills":[]}}"#, "user", ""),
            (#"{"channel":"notification","data":{"notification":"x"}}"#, "notification", ""),
            (#"{"channel":"userFills","data":{"user":"0x00000000000000000000000000000000000000A2","fills":[]}}"#, "userFills", "0x00000000000000000000000000000000000000a2"),
            (#"{"channel":"userFundings","data":{"isSnapshot":true,"user":"0xab","fundings":[]}}"#, "userFundings", "0xab"),
            (#"{"channel":"userNonFundingLedgerUpdates","data":{"user":"0xab","nonFundingLedgerUpdates":[]}}"#, "userNonFundingLedgerUpdates", "0xab"),
            (#"{"channel":"userTwapSliceFills","data":{"user":"0xab","twapSliceFills":[]}}"#, "userTwapSliceFills", "0xab"),
            (#"{"channel":"userTwapHistory","data":{"user":"0xab","history":[]}}"#, "userTwapHistory", "0xab"),
            (#"{"channel":"spotState","data":{"user":"0xab","spotState":{"balances":[]}}}"#, "spotState", "0xab"),
            (#"{"channel":"clearinghouseState","data":{"dex":"xyz","user":"0xab","clearinghouseState":{}}}"#, "clearinghouseState", "0xab,xyz"),
            (#"{"channel":"openOrders","data":{"dex":"","user":"0xab","orders":[]}}"#, "openOrders", "0xab,"),
            (#"{"channel":"twapStates","data":{"dex":"","user":"0xab","states":[]}}"#, "twapStates", "0xab,"),
            (#"{"channel":"activeAssetData","data":{"user":"0xab","coin":"BTC"}}"#, "activeAssetData", "BTC,0xab"),
        ])
        func `an account push is routed by its channel and the fields from its own data`(
            frame: String, channel: String, key: String
        ) {
            #expect(StreamConnection.topic(of: Data(frame.utf8)) == .init(channel: channel, key: key))
        }

        @Test(arguments: [
            #"{"channel":"userFills","data":{"fills":[]}}"#,
            #"{"channel":"clearinghouseState","data":{"user":"0xab","clearinghouseState":{}}}"#,
            #"{"channel":"activeAssetData","data":{"coin":"BTC"}}"#,
            #"{"channel":"webData3","data":{"userState":{}}}"#,
        ])
        func `account pushes missing their routing fields, and channels no stream reads, have no topic`(frame: String) {
            #expect(StreamConnection.topic(of: Data(frame.utf8)) == nil)
        }
    }
}
