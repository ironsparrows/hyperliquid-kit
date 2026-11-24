import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Compressed market feeds", .timeLimit(.minutes(1)))
    struct MarketFeedsTests {
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5},{"name":"ETH","szDecimals":4}]}"#

        private static func streams(_ transport: FakeWebSocketTransport, http: FakeTransport = FakeTransport(json: meta))
            -> (Streams, StreamConnection)
        {
            let connection = StreamConnection(
                url: URL(string: "wss://example.invalid/ws")!, transport: transport, directory: AssetDirectory(info: .test(http))
            )
            return (Streams(connection: connection), connection)
        }

        // MARK: Subscriptions

        @Test func `each feed sends its subscription as the subscriptions page writes it`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let readers = [
                Task { for try await _ in streams.orderBookUpdates("BTC", precision: .fiveSignificantFigures(mantissa: .two)) {} },
                Task { for try await _ in streams.prices() {} },
                Task { for try await _ in streams.assetContexts() {} },
            ]
            let session = try await transport.session()
            #expect(Set(try await session.sent(atLeast: 3)) == [
                #"{"method":"subscribe","subscription":{"type":"l2","c":"BTC","s":5,"m":2}}"#,
                #"{"method":"subscribe","subscription":{"type":"fastAssetCtxs"}}"#,
                #"{"method":"subscribe","subscription":{"type":"pac"}}"#,
            ])
            for reader in readers { reader.cancel() }
            await connection.disconnect()
        }

        @Test func `a second stream of a feed is refused while the first lasts, and starts cleanly after it ends`()
            async throws
        {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let first = Task { for try await _ in streams.prices() {} }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await #expect {
                for try await _ in streams.prices() {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            first.cancel()
            _ = try await session.sent(atLeast: 2)
            let next = Task { for try await _ in streams.prices() {} }
            #expect(try await session.sent(atLeast: 3) == [
                #"{"method":"subscribe","subscription":{"type":"fastAssetCtxs"}}"#,
                #"{"method":"unsubscribe","subscription":{"type":"fastAssetCtxs"}}"#,
                #"{"method":"subscribe","subscription":{"type":"fastAssetCtxs"}}"#,
            ])
            next.cancel()
            await connection.disconnect()
        }

        // MARK: Order book updates

        @Test func `the recorded BTC diffs rebuild the books Hyperliquid pushed at the same times`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var updates = streams.orderBookUpdates("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            var rebuilt: [Date: Hyperliquid.OrderBook] = [:]
            var pushed: [Hyperliquid.OrderBook] = []
            for frame in try Fixture.frames("ws_l2") {
                let topic = StreamConnection.topic(of: Data(frame.utf8))
                if topic == .init(channel: "l2Book", key: "BTC") {
                    pushed.append(try JSONDecoder().decode(Push.self, from: Data(frame.utf8)).data)
                    continue
                }
                await session.push(frame)
                if topic == .init(channel: "l2", key: "BTC") {
                    let book = try #require(try await updates.next())
                    rebuilt[book.time] = book
                }
            }
            #expect(rebuilt.count == 25)
            #expect(pushed.count == 3)
            func levels(_ side: [Hyperliquid.OrderBook.Level]) -> [[Decimal]] { side.map { [$0.price, $0.size] } }
            for book in pushed {
                let built = try #require(rebuilt[book.time])
                #expect(levels(built.bids) == levels(book.bids))
                #expect(levels(built.asks) == levels(book.asks))
            }
            await connection.disconnect()
        }

        @Test func `every recorded diff is applied when the reader reads only at the end`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var updates = streams.orderBookUpdates("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            var last: Hyperliquid.OrderBook?
            for frame in try Fixture.frames("ws_l2") {
                if StreamConnection.topic(of: Data(frame.utf8)) == .init(channel: "l2Book", key: "BTC") {
                    last = try JSONDecoder().decode(Push.self, from: Data(frame.utf8)).data
                } else {
                    await session.push(frame)
                }
            }
            let expected = try #require(last)
            var book = try #require(try await updates.next())
            while book.time < expected.time { book = try #require(try await updates.next()) }
            #expect(book.bids.map(\.price) == expected.bids.map(\.price))
            #expect(book.asks.map(\.size) == expected.asks.map(\.size))
            await connection.disconnect()
        }

        private static let snapshot =
            #"{"channel":"l2","data":{"s":{"coin":"BTC","time":1,"levels":[[{"px":"10","sz":"1","n":2}],[{"px":"11","sz":"1","n":1}]]}}}"#

        @Test func `a diff before the snapshot is skipped, and a plain diff after it changes the book`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var updates = streams.orderBookUpdates("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(#"{"channel":"l2","data":{"u":{"c":"BTC","t":1,"l":[[{"p":"1","s":"1"}],[]],"r":[[],[]]}}}"#)
            await session.push(Self.snapshot)
            #expect(try await updates.next()?.bids.map(\.price) == [10])
            await session.push(#"{"channel":"l2","data":{"u":{"c":"BTC","t":2,"l":[[{"p":"9","s":"3"}],[]],"r":[[],[0]]}}}"#)
            let changed = try #require(try await updates.next())
            #expect(changed.bids.map(\.price) == [10, 9])
            #expect(changed.asks.isEmpty)
            await connection.disconnect()
        }

        @Test func `a diff that doesn't fit the book ends the stream with an unexpected response`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var updates = streams.orderBookUpdates("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(Self.snapshot)
            _ = try await updates.next()
            // A compressed diff, `{"c":"BTC","t":2,"l":[[],[]],"r":[[5],[]]}`, removing a level the book lacks.
            await session.push(#"{"channel":"l2","data":{"c":"q1ZKVrJScgpxVtJRKlGyMtJRylGyio6O1YmOjdVRKgKxTcGcWgA="}}"#)
            await #expect {
                _ = try await updates.next()
            } throws: { error in
                (error as? HyperliquidError)?.kind == .unexpectedResponse
            }
            await connection.disconnect()
        }

        @Test func `a diff that doesn't inflate ends every book update stream with a decoding error`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var btc = streams.orderBookUpdates("BTC").makeAsyncIterator()
            var eth = streams.orderBookUpdates("ETH").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.push(#"{"channel":"l2","data":{"c":"AAAA"}}"#)
            await #expect(throws: DecodingError.self) { _ = try await btc.next() }
            await #expect(throws: DecodingError.self) { _ = try await eth.next() }
            await connection.disconnect()
        }

        @Test func `a prices push that doesn't inflate ends the stream with a decoding error`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var prices = streams.prices().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(#"{"channel":"fastAssetCtxs","data":"not base64!"}"#)
            await #expect(throws: DecodingError.self) { _ = try await prices.next() }
            await connection.disconnect()
        }

        @Test func `a diff removes by index into the book as it was, then adds or replaces by price`() throws {
            var state = OrderBookState(snapshot: .init(
                coin: "BTC", time: .init(timeIntervalSince1970: 0),
                bids: [.init(price: 10, size: 1, orderCount: 3), .init(price: 9, size: 1, orderCount: 1), .init(price: 8, size: 1, orderCount: 1)],
                asks: [.init(price: 11, size: 1, orderCount: 1)]
            ))
            let diff = try JSONDecoder().decode(
                OrderBookDiff.self,
                from: Data(#"{"c":"BTC","t":5000,"l":[[{"p":"10","s":"2"},{"p":"9.5","s":"4"}],[{"p":"12","s":"3"}]],"r":[[1,2],[]]}"#.utf8)
            )
            try state.apply(diff)
            #expect(state.book.time == Date(timeIntervalSince1970: 5))
            #expect(state.book.bids == [.init(price: 10, size: 2, orderCount: nil), .init(price: 9.5, size: 4, orderCount: nil)])
            #expect(state.book.asks.map(\.price) == [11, 12])
        }

        // MARK: Prices and perpetual contexts

        @Test func `recorded prices merge into every market's latest mark and mid`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var prices = streams.prices().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            let frames = try Fixture.frames("ws_fastAssetCtxs")
            // Every push is merged, though the reader reads only after the last.
            for frame in frames { await session.push(frame) }
            // The reader gets some of the elements, ending with the state after the last push.
            let finalBTC = Hyperliquid.MarketPrices(markPrice: Decimal(60207), midPrice: Decimal(string: "60198.5"))
            var latest = try #require(try await prices.next())
            var read = 1
            while read < frames.count, latest.count < 1839 || latest["BTC"] != finalBTC {
                latest = try #require(try await prices.next())
                read += 1
            }
            #expect(latest.count == 1839)
            #expect(latest["BTC"] == finalBTC)
            #expect(latest.values.filter { $0.midPrice == nil }.count == 683)
            // The last push for io:EWY has only a mid; the mark stays from an earlier push.
            #expect(latest["io:EWY"] == .init(markPrice: Decimal(string: "135.62"), midPrice: Decimal(string: "135.665")))
            await connection.disconnect()
        }

        @Test func `recorded asset contexts merge by position, naming the perp DEXs whose lists load`() async throws {
            let transport = FakeWebSocketTransport()
            let meta = String(decoding: try Fixture.data("meta"), as: UTF8.self)
            let cash = String(decoding: try Fixture.data("meta_cash"), as: UTF8.self)
            let http = FakeTransport { body in
                switch body {
                case #"{"type":"meta","dex":""}"#: .json(meta)
                case #"{"type":"meta","dex":"cash"}"#: .json(cash)
                default: .init(status: 500, body: Data("null".utf8))
                }
            }
            let (streams, connection) = Self.streams(transport, http: http)
            var contexts = streams.assetContexts().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            let frames = try Fixture.frames("ws_pac")
            // The lists load in the background; later pushes, here repeats of the last, name them.
            for frame in frames { await session.push(frame) }
            var merged = try #require(try await contexts.next())
            while Set(merged.keys.map(\.dex)) != [.first, .named("cash")] {
                await session.push(frames[1])
                merged = try #require(try await contexts.next())
            }
            #expect(merged["cash:CAR"] != nil)
            #expect(merged["BTC"] == .init(
                markPrice: 60207, midPrice: Decimal(string: "60198.5"), oraclePrice: 60239, previousDayPrice: 61236,
                funding: Decimal(string: "0.0000002258")!, premium: nil, openInterest: Decimal(string: "37551.6997999999")!,
                dayNotionalVolume: Decimal(string: "4748772806.7526988983")!, dayBaseVolume: Decimal(string: "76612.8752499998"),
                impactBidPrice: nil, impactAskPrice: nil
            ))
            await connection.disconnect()
        }

        @Test func `a perp DEX's snapshot waits for its list, and one whose list fails stays out`() async throws {
            let snapshot = try JSONDecoder().decode(
                [AssetContextUpdate].self,
                from: Data(#"[{"markPx":"2","oraclePx":"2","prevDayPx":"1","funding":"0.1","openInterest":"5","dayNtlVlm":"9"},{}]"#.utf8)
            )
            let http = FakeTransport { body in
                body.contains(#""dex":"cash""#)
                    ? .json(#"{"universe":[{"name":"cash:A","szDecimals":1},{"name":"cash:B","szDecimals":1}]}"#)
                    : .init(status: 500, body: Data("null".utf8))
            }
            let directory = AssetDirectory(info: .test(http))
            var state = AssetContextsState()
            state.merge(snapshot, on: .named("cash"))
            state.merge(snapshot, on: .named("gone"))
            state.nameContexts(loadingNamesFrom: directory)
            state.merge([try JSONDecoder().decode(AssetContextUpdate.self, from: Data(#"{"markPx":"3"}"#.utf8))], on: .named("cash"))
            try await eventually {
                state.nameContexts(loadingNamesFrom: directory)
                return state.contexts.isEmpty ? nil : true
            }
            #expect(state.contexts.keys.map(\.name) == ["cash:A"])
            #expect(state.contexts["cash:A"]?.markPrice == 3)
            // Each list is asked for once.
            #expect(await http.requests.count == 2)
        }

        @Test func `a null clears a context field, and a context appears once its required fields arrive`() throws {
            func update(_ json: String) throws -> AssetContextUpdate {
                try JSONDecoder().decode(AssetContextUpdate.self, from: Data(json.utf8))
            }
            var fields = AssetContextFields()
            fields.merge(try update(#"{"markPx":"2","midPx":"2.5"}"#))
            #expect(fields.context == nil)
            fields.merge(try update(#"{"oraclePx":"2","prevDayPx":"1","funding":"0.1","openInterest":"5","dayNtlVlm":"9"}"#))
            #expect(fields.context?.midPrice == Decimal(string: "2.5"))
            fields.merge(try update(#"{"midPx":null}"#))
            #expect(fields.context?.midPrice == nil)
            #expect(try update("{}").isEmpty)
            fields.merge(try update("{}"))
            #expect(fields.context?.markPrice == 2)
        }

        // MARK: Routing

        @Test func `a compressed diff is inflated while routing, and the whole-market feeds route by channel`() throws {
            let diff = try #require(try Fixture.frames("ws_l2").first { $0.contains(#""data":{"c":"#) })
            let routedDiff = try #require(StreamConnection.routed(Data(diff.utf8)))
            guard case .topic(let topic) = routedDiff.destination else {
                Issue.record("Expected a topic, got \(routedDiff.destination)")
                return
            }
            #expect(topic.channel == "l2")
            #expect(String(decoding: routedDiff.push.prefix(13), as: UTF8.self) == #"{"data":{"u":"#)
            for (name, channel) in [("ws_pac", "pac"), ("ws_fastAssetCtxs", "fastAssetCtxs")] {
                let frame = try #require(try Fixture.frames(name).first)
                #expect(StreamConnection.topic(of: Data(frame.utf8)) == .init(channel: channel, key: ""))
            }
        }

        @Test func `a compressed diff that doesn't inflate goes to every book update stream, another shape nowhere`() {
            #expect(StreamConnection.routed(Data(#"{"channel":"l2","data":{"c":"AAAA"}}"#.utf8))?.destination == .channel("l2"))
            #expect(StreamConnection.routed(Data(#"{"channel":"l2","data":{}}"#.utf8)) == nil)
        }

        private struct Push: Decodable {
            let data: Hyperliquid.OrderBook
        }
    }
}
