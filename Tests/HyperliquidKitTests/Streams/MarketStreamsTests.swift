import Foundation
import Testing

@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Market streams", .timeLimit(.minutes(1)))
    struct MarketStreamsTests {
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5},{"name":"ETH","szDecimals":4}]}"#

        private static func streams(_ transport: FakeWebSocketTransport) -> (Streams, StreamConnection) {
            let connection = StreamConnection(
                url: URL(string: "wss://example.invalid/ws")!, transport: transport,
                directory: AssetDirectory(info: .test(FakeTransport(json: Self.meta)))
            )
            return (Streams(connection: connection), connection)
        }

        private static func book(_ coin: String, _ price: Int) -> String {
            #"{"channel":"l2Book","data":{"coin":"\#(coin)","time":1795530169945,"levels":[[{"px":"\#(price)","sz":"1","n":1}],[]]}}"#
        }

        private static func trade(_ tid: Int) -> String {
            #"{"coin":"BTC","side":"A","px":"60321.0","sz":"0.01","time":1795530160280,"hash":"0x0000000000000000000000000000000000000000000000000000000000000000","tid":\#(tid),"users":["0x0000000000000000000000000000000000000001","0x0000000000000000000000000000000000000002"]}"#
        }

        private static func candle(_ interval: String, close: String) -> String {
            #"{"t":1795530120000,"T":1795530179999,"s":"BTC","i":"\#(interval)","o":"1","c":"\#(close)","h":"1","l":"1","v":"1","n":1}"#
        }

        // MARK: Subscriptions

        @Test func `each stream sends its subscription as the subscriptions page writes it`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let readers = [
                Task { for try await _ in streams.orderBook("BTC", precision: .fiveSignificantFigures(mantissa: .two)) {} },
                Task { for try await _ in streams.bestBidOffer("BTC") {} },
                Task { for try await _ in streams.trades("BTC") {} },
                Task { for try await _ in streams.candles("BTC", interval: .oneMinute) {} },
                Task { for try await _ in streams.assetContext("BTC") {} },
            ]
            let session = try await transport.session()
            let sent = Set(try await session.sent(atLeast: 5))
            #expect(
                sent == [
                    #"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":5,"mantissa":2}}"#,
                    #"{"method":"subscribe","subscription":{"type":"bbo","coin":"BTC"}}"#,
                    #"{"method":"subscribe","subscription":{"type":"trades","coin":"BTC"}}"#,
                    #"{"method":"subscribe","subscription":{"type":"candle","coin":"BTC","interval":"1m"}}"#,
                    #"{"method":"subscribe","subscription":{"type":"activeAssetCtx","coin":"BTC"}}"#,
                ])
            for reader in readers { reader.cancel() }
            await connection.disconnect()
        }

        @Test func `a spot coin is refused without a connection`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, _) = Self.streams(transport)
            await #expect {
                for try await _ in streams.orderBook("@107") {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
            }
            #expect(await transport.sessions.isEmpty)
        }

        @Test func `a second precision of a streaming book is refused, the same precision shares it`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let full = Task { for try await _ in streams.orderBook("BTC") {} }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await #expect {
                for try await _ in streams.orderBook("BTC", precision: .significantFigures(.three)) {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            var shared = streams.orderBook("BTC", precision: .full).makeAsyncIterator()
            try await eventually { await connection.bookkeeping.consumers == 2 ? true : nil }
            // The shared stream is subscribed once it reads a push.
            let pusher = Task {
                while !Task.isCancelled {
                    await session.push(Self.book("BTC", 1))
                    try? await Task.sleep(for: .milliseconds(1))
                }
            }
            #expect(try await shared.next() != nil)
            pusher.cancel()
            #expect(await session.sent.count == 1)
            full.cancel()
            await connection.disconnect()
        }

        @Test func `switching a book's precision unsubscribes the old one before subscribing the new one`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            let full = Task { for try await _ in streams.orderBook("BTC") {} }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            full.cancel()
            let grouped = Task { for try await _ in streams.orderBook("BTC", precision: .significantFigures(.five)) {} }
            #expect(
                try await session.sent(atLeast: 3) == [
                    #"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC"}}"#,
                    #"{"method":"unsubscribe","subscription":{"type":"l2Book","coin":"BTC"}}"#,
                    #"{"method":"subscribe","subscription":{"type":"l2Book","coin":"BTC","nSigFigs":5}}"#,
                ])
            grouped.cancel()
            await connection.disconnect()
            try await eventually {
                let state = await connection.bookkeeping
                return state == (0, 0, 0, 0, 0) ? true : nil
            }
        }

        // MARK: Routing and buffering

        @Test func `books reach only their coin's stream`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var btc = streams.orderBook("BTC").makeAsyncIterator()
            var eth = streams.orderBook("ETH").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.push(Self.book("ETH", 1700))
            await session.push(Self.book("BTC", 60000))
            #expect(try await btc.next()?.bids.first?.price == 60000)
            #expect(try await eth.next()?.bids.first?.price == 1700)
            await connection.disconnect()
        }

        @Test func `a book stream a slow reader falls behind on ends at the latest book`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var books = streams.orderBook("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            for price in 1...50 { await session.push(Self.book("BTC", price)) }
            var read: [Decimal] = []
            while let price = try await books.next()?.bids.first?.price {
                read.append(price)
                if price == 50 { break }
            }
            #expect(read.last == 50)
            #expect(zip(read, read.dropFirst()).allSatisfy { $0 < $1 })
            await connection.disconnect()
        }

        @Test func `trades keep every batch in order and drop an empty push`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var trades = streams.trades("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(#"{"channel":"trades","data":[]}"#)
            for tid in stride(from: 1, through: 99, by: 2) {
                await session.push(#"{"channel":"trades","data":[\#(Self.trade(tid)),\#(Self.trade(tid + 1))]}"#)
            }
            var batches: [[UInt64]] = []
            while batches.count < 50, let batch = try await trades.next() { batches.append(batch.map(\.id.rawValue)) }
            #expect(batches.count == 50)
            #expect(batches.allSatisfy { $0.count == 2 })
            #expect(batches.flatMap(\.self) == Array(1...100))
            await connection.disconnect()
        }

        @Test func `candles are routed by interval, every update kept, a list push included`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var minute = streams.candles("BTC", interval: .oneMinute).makeAsyncIterator()
            var fiveMinutes = streams.candles("BTC", interval: .fiveMinutes).makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.push(#"{"channel":"candle","data":\#(Self.candle("5m", close: "5"))}"#)
            await session.push(#"{"channel":"candle","data":\#(Self.candle("1m", close: "1"))}"#)
            await session.push(#"{"channel":"candle","data":[\#(Self.candle("1m", close: "2")),\#(Self.candle("1m", close: "3"))]}"#)
            #expect(try await minute.next()?.close == 1)
            #expect(try await minute.next()?.close == 2)
            #expect(try await minute.next()?.close == 3)
            #expect(try await fiveMinutes.next()?.close == 5)
            await connection.disconnect()
        }

        @Test func `asset contexts and best bids and offers reach their coin's stream`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var context = streams.assetContext("BTC").makeAsyncIterator()
            var best = streams.bestBidOffer("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.push(
                #"{"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{"funding":"0.0000125","openInterest":"1","prevDayPx":"1","dayNtlVlm":"1","oraclePx":"1","markPx":"60000.0"}}}"#
            )
            await session.push(#"{"channel":"bbo","data":{"coin":"BTC","time":1795530170160,"bbo":[null,null]}}"#)
            #expect(try await context.next()?.markPrice == 60000)
            let quote = try await best.next()
            #expect(quote?.bid == nil && quote?.ask == nil)
            await connection.disconnect()
        }

        @Test func `a recorded asset context push reads through the stream`() async throws {
            let transport = FakeWebSocketTransport()
            let (streams, connection) = Self.streams(transport)
            var context = streams.assetContext("BTC").makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(
                #"{"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{"funding":"-0.0000015398","openInterest":"36772.2364999999","prevDayPx":"64236.0","dayNtlVlm":"3964361098.8869256973","premium":"-0.0005472357","oraclePx":"60359.0","markPx":"60326.0","midPx":"60326.5","impactPxs":["60326.0","60327.0"],"dayBaseVlm":"63297.6587900001"}}}"#
            )
            let ctx = try #require(try await context.next())
            #expect(ctx.funding == Decimal(string: "-0.0000015398"))
            #expect(ctx.impactAskPrice == Decimal(60327))
            await connection.disconnect()
        }

        @Test(arguments: [
            (#"{"channel":"l2Book","data":{"coin":"BTC","time":1,"levels":[[],[]]}}"#, "l2Book", "BTC"),
            (#"{"channel":"bbo","data":{"coin":"xyz:XYZ100","time":1,"bbo":[null,null]}}"#, "bbo", "xyz:XYZ100"),
            (#"{"channel":"trades","data":[{"coin":"ETH"}]}"#, "trades", "ETH"),
            (#"{"channel":"candle","data":{"s":"BTC","i":"15m"}}"#, "candle", "BTC,15m"),
            (#"{"channel":"candle","data":[{"s":"BTC","i":"1h"}]}"#, "candle", "BTC,1h"),
            (#"{"channel":"activeAssetCtx","data":{"coin":"BTC","ctx":{}}}"#, "activeAssetCtx", "BTC"),
            (#"{"channel":"allMids","data":{"mids":{},"dex":"xyz"}}"#, "allMids", "xyz"),
        ])
        func `a push is routed by its channel and the field from its own data`(frame: String, channel: String, key: String) {
            #expect(StreamRouter.topic(of: Data(frame.utf8)) == .init(channel: channel, key: key))
        }

        @Test(arguments: [
            #"{"channel":"trades","data":[]}"#, #"{"channel":"activeSpotAssetCtx","data":{"coin":"@107","ctx":{}}}"#,
            #"{"channel":"error","data":"Already subscribed"}"#, #"{"channel":"pong"}"#, "Websocket connection established.",
            #"{"channel":"allMids","data":"unreadable"}"#,
        ])
        func `frames no stream reads have no topic`(frame: String) {
            #expect(StreamRouter.topic(of: Data(frame.utf8)) == nil)
        }
    }
}
