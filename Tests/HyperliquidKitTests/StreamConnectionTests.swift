import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Stream connection", .timeLimit(.minutes(1)))
    struct StreamConnectionTests {
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5}]}"#
        private static let subscribeFirst = #"{"method":"subscribe","subscription":{"type":"allMids"}}"#
        private static let unsubscribeFirst = #"{"method":"unsubscribe","subscription":{"type":"allMids"}}"#
        private static let perpDexs = #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#

        private static func mids(_ mids: String, dex: String? = nil) -> String {
            let dexField = dex.map { #","dex":"\#($0)""# } ?? ""
            return #"{"channel":"allMids","data":{"mids":{\#(mids)}\#(dexField)}}"#
        }

        private static func connection(
            _ transport: FakeWebSocketTransport, http: FakeTransport = FakeTransport(), pingInterval: Duration = .seconds(50)
        ) -> StreamConnection {
            StreamConnection(
                url: URL(string: "wss://example.invalid/ws")!, transport: transport,
                directory: AssetDirectory(info: .test(http)), pingInterval: pingInterval
            )
        }

        // MARK: Subscribing and routing

        @Test func `the connection opens with the first stream and sends its subscription`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport))
            #expect(await transport.sessions.isEmpty)
            var mids = streams.mids().makeAsyncIterator()
            let session = try await transport.session()
            #expect(try await session.sent(atLeast: 1) == [Self.subscribeFirst])
            await session.push(Self.mids(#""BTC":"60000.5","@107":"62.3""#))
            #expect(try await mids.next() == ["BTC": Decimal(string: "60000.5")!, "@107": Decimal(string: "62.3")!])
        }

        @Test func `pushes reach only the streams of their perp DEX, in order`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport, http: FakeTransport(json: Self.perpDexs)))
            var first = streams.mids().makeAsyncIterator()
            var xyz = streams.mids(dex: .named("xyz")).makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.push(Self.mids(#""xyz:A":"1""#, dex: "xyz"))
            #expect(try await xyz.next() == ["xyz:A": 1])
            await session.push(Self.mids(#""BTC":"1""#))
            #expect(try await first.next() == ["BTC": 1])
            await session.push(Self.mids(#""xyz:A":"2""#, dex: "xyz"))
            #expect(try await xyz.next() == ["xyz:A": 2])
        }

        @Test func `frames no stream reads are dropped`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport))
            var mids = streams.mids().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            for frame in [
                "Websocket connection established.", #"{"channel":"pong"}"#, #"{"channel":"error","data":"Already subscribed"}"#,
                #"{"channel":"subscriptionResponse","data":{"method":"subscribe"}}"#, #"{"channel":"trades","data":[]}"#,
                Self.mids(#""BTC":"9""#, dex: "other"),
            ] {
                await session.push(frame)
            }
            await session.push(Self.mids(#""BTC":"1""#))
            #expect(try await mids.next() == ["BTC": 1])
        }

        @Test func `streams of one subscription share it, and the last to end unsubscribes`() async throws {
            let transport = FakeWebSocketTransport()
            let connection = Self.connection(transport)
            let streams = Streams(connection: connection)
            let one = Task { for try await _ in streams.mids() {} }
            let two = Task { for try await _ in streams.mids() {} }
            let session = try await transport.session()
            try await eventually { await connection.bookkeeping.consumers == 2 ? true : nil }
            _ = try await session.sent(atLeast: 1)
            one.cancel()
            try await eventually { await connection.bookkeeping.consumers == 1 ? true : nil }
            #expect(await session.sent == [Self.subscribeFirst])
            two.cancel()
            #expect(try await session.sent(atLeast: 2) == [Self.subscribeFirst, Self.unsubscribeFirst])
            try await Self.expectEmpty(connection)
        }

        /// Waits until every subscription the session sent was removed again.
        private static func expectBalanced(_ session: FakeWebSocketSession) async throws {
            try await eventually {
                let sent = await session.sent
                let subscribes = sent.count(where: { $0.contains(#""method":"subscribe""#) })
                let unsubscribes = sent.count(where: { $0.contains(#""method":"unsubscribe""#) })
                return subscribes == unsubscribes ? true : nil
            }
        }

        /// How a racing stream ended, once it has.
        private actor Outcome {
            var value: Bool?
            func set(_ value: Bool) { self.value = value }
        }

        /// Waits until the connection tracks no stream and no subscription.
        private static func expectEmpty(_ connection: StreamConnection) async throws {
            try await eventually {
                let state = await connection.bookkeeping
                return state == (0, 0, 0, 0, 0) ? true : nil
            }
        }

        @Test func `a push that doesn't decode ends its stream with the error`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport))
            var mids = streams.mids().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(#"{"channel":"allMids","data":{"mids":{"BTC":"not a number"}}}"#)
            await #expect(throws: DecodingError.self) { _ = try await mids.next() }
        }

        // MARK: Coins

        @Test func `an unknown or spot coin, or an unknown perp DEX, is refused before connecting`() async throws {
            let transport = FakeWebSocketTransport()
            let connection = Self.connection(transport, http: FakeTransport(responses: [.json(Self.meta), .json(Self.perpDexs)]))
            let refused: [(StreamConnection.Subscription, Hyperliquid.ClientError.Reason)] = [
                (.init(topic: .init(channel: "trades", key: "NOPE"), request: ["type": "trades"], coin: "NOPE"), .unknownCoin),
                (.init(topic: .init(channel: "trades", key: "@107"), request: ["type": "trades"], coin: "@107"), .unsupportedMarket),
                (.allMids(.named("nope")), .unknownCoin),
            ]
            for (subscription, reason) in refused {
                let stream = connection.stream(subscription, bufferingPolicy: .unbounded) { $0 }
                await #expect {
                    for try await _ in stream {}
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == reason
                }
            }
            #expect(await transport.sessions.isEmpty)
            try await Self.expectEmpty(connection)
        }

        @Test func `a known coin passes the check and subscribes`() async throws {
            let transport = FakeWebSocketTransport()
            let connection = Self.connection(transport, http: FakeTransport(json: Self.meta))
            let subscription = StreamConnection.Subscription(
                topic: .init(channel: "trades", key: "BTC"), request: ["type": "trades", "coin": "BTC"], coin: "BTC"
            )
            let reading = Task { for try await _ in connection.stream(subscription, bufferingPolicy: .unbounded, decode: { $0 }) {} }
            let session = try await transport.session()
            #expect(try await session.sent(atLeast: 1) == [#"{"method":"subscribe","subscription":{"type":"trades","coin":"BTC"}}"#])
            reading.cancel()
            await connection.disconnect()
        }

        @Test func `a stream dropped before it subscribes, or during its coin check, leaves nothing behind`() async throws {
            let transport = FakeWebSocketTransport()
            let connection = Self.connection(transport, http: FakeTransport(json: Self.meta))
            let subscription = StreamConnection.Subscription(
                topic: .init(channel: "trades", key: "BTC"), request: ["type": "trades", "coin": "BTC"], coin: "BTC"
            )
            for _ in 0..<50 {
                _ = connection.stream(subscription, bufferingPolicy: .unbounded) { $0 }
            }
            try await Self.expectEmpty(connection)
            // A stream may win the race and subscribe before its end arrives; every subscription is removed.
            for session in await transport.sessions { try await Self.expectBalanced(session) }
        }

        // MARK: Connection

        @Test func `a failed connection ends the stream with its error`() async {
            let transport = FakeWebSocketTransport()
            await transport.fail(with: Hyperliquid.ClientError(.connectionFailed))
            await #expect {
                let streams = Streams(connection: Self.connection(transport))
                for try await _ in streams.mids() {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .connectionFailed
            }
        }

        @Test func `after a failed connection the next stream connects again`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport))
            await transport.fail(with: Hyperliquid.ClientError(.connectionFailed))
            await #expect(throws: Hyperliquid.ClientError.self) {
                for try await _ in streams.mids() {}
            }
            await transport.fail(with: nil)
            var mids = streams.mids().makeAsyncIterator()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await session.push(Self.mids(#""BTC":"3""#))
            #expect(try await mids.next() == ["BTC": 3])
        }

        @Test func `a stream created before a disconnect doesn't subscribe after it`() async throws {
            let transport = FakeWebSocketTransport()
            let connection = Self.connection(transport)
            let streams = Streams(connection: connection)
            let stream = streams.mids()
            await streams.disconnect()
            for try await _ in stream {}
            try await Self.expectEmpty(connection)
            // The stream may connect before the disconnect reaches the connection; then that connection is closed.
            for session in await transport.sessions { #expect(await session.isClosed) }
        }

        @Test func `a dropped connection ends every stream, and the next stream connects again`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport, http: FakeTransport(json: Self.perpDexs)))
            let first = streams.mids()
            let xyz = streams.mids(dex: .named("xyz"))
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 2)
            await session.drop()
            for stream in [first, xyz] {
                await #expect {
                    for try await _ in stream {}
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .connectionClosed
                }
            }
            var again = streams.mids().makeAsyncIterator()
            let second = try await eventually { await transport.sessions.count == 2 ? transport.sessions.last : nil }
            #expect(try await second.sent(atLeast: 1) == [Self.subscribeFirst])
            await second.push(Self.mids(#""BTC":"2""#))
            #expect(try await again.next() == ["BTC": 2])
        }

        @Test func `a subscription sent just before the connection drops ends its stream with the error`() async throws {
            for _ in 0..<50 {
                let transport = FakeWebSocketTransport()
                let connection = Self.connection(transport, http: FakeTransport(json: Self.perpDexs))
                let streams = Streams(connection: connection)
                let first = streams.mids()
                let session = try await transport.session()
                _ = try await session.sent(atLeast: 1)
                // The second subscription races the drop: it is sent on the dying connection, or opens a new one.
                let racing = streams.mids(dex: .named("xyz"))
                await session.drop()
                await #expect(throws: Hyperliquid.ClientError.self) { for try await _ in first {} }
                let outcome = Outcome()
                let ended = Task {
                    do {
                        for try await _ in racing {}
                        await outcome.set(false)
                    } catch {
                        await outcome.set((error as? Hyperliquid.ClientError)?.reason == .connectionClosed)
                    }
                    return await outcome.value ?? false
                }
                // Either the stream ends, or it opens a second connection.
                try await eventually {
                    if await outcome.value != nil { return true }
                    return await transport.sessions.count > 1 ? true : nil
                }
                if await transport.sessions.count > 1 {
                    // It subscribed on a new connection: that one drops too, and the stream ends.
                    let second = try await transport.session()
                    _ = try await second.sent(atLeast: 1)
                    await second.drop()
                }
                #expect(await ended.value)
                try await Self.expectEmpty(connection)
            }
        }

        @Test func `disconnecting closes the connection and ends every stream without an error`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport))
            let reading = Task { for try await _ in streams.mids() {} }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            await streams.disconnect()
            try await reading.value
            #expect(await session.isClosed)
        }

        @Test func `the connection pings on its interval`() async throws {
            let transport = FakeWebSocketTransport()
            let streams = Streams(connection: Self.connection(transport, pingInterval: .milliseconds(20)))
            let reading = Task { for try await _ in streams.mids() {} }
            let session = try await transport.session()
            let sent = try await session.sent(atLeast: 3)
            #expect(sent.first == Self.subscribeFirst)
            #expect(sent.dropFirst().allSatisfy { $0 == #"{"method":"ping"}"# })
            reading.cancel()
            await streams.disconnect()
        }

        @Test func `a released connection ends its streams with connection closed`() async throws {
            let transport = FakeWebSocketTransport()
            var connection: StreamConnection? = Self.connection(transport)
            let stream = try #require(connection).stream(.allMids(.first), bufferingPolicy: .unbounded) { $0 }
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            connection = nil
            await #expect {
                for try await _ in stream {}
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .connectionClosed
            }
            try await eventually { await session.isClosed ? true : nil }
        }

        @Test func `a released client closes its connection`() async throws {
            let transport = FakeWebSocketTransport()
            var client: Hyperliquid.Client? = Hyperliquid.Client(
                configuration: .init(), transport: FakeTransport(), webSocketTransport: transport
            )
            let stream = try #require(client).stream.mids()
            let session = try await transport.session()
            _ = try await session.sent(atLeast: 1)
            client = nil
            try await eventually { await session.isClosed ? true : nil }
            for try await _ in stream {}
        }

        // MARK: Stress

        @Test func `many streams that start and end, with disconnects between, leave nothing behind`() async throws {
            let transport = FakeWebSocketTransport()
            let connection = Self.connection(transport, http: FakeTransport(responses: (0..<40).map { _ in .json(Self.perpDexs) }))
            let streams = Streams(connection: connection)
            for round in 0..<20 {
                let consumers = (0..<25).map { index in
                    Task {
                        var mids = streams.mids(dex: index.isMultiple(of: 2) ? .first : .named("xyz")).makeAsyncIterator()
                        if index.isMultiple(of: 3) { _ = try await mids.next() }
                    }
                }
                let session = try await eventually { await transport.sessions.count == round + 1 ? transport.sessions.last : nil }
                let pusher = Task {
                    while !Task.isCancelled {
                        await session.push(Self.mids(#""BTC":"1""#))
                        await session.push(Self.mids(#""xyz:A":"1""#, dex: "xyz"))
                        try? await Task.sleep(for: .milliseconds(1))
                    }
                }
                for consumer in consumers { try await consumer.value }
                pusher.cancel()
                if !round.isMultiple(of: 2) {
                    // Every subscription was removed: each one sent is matched by an unsubscription.
                    try await eventually {
                        let sent = await session.sent
                        let subscribes = sent.count(where: { $0.contains(#""method":"subscribe""#) })
                        let unsubscribes = sent.count(where: { $0.contains(#""method":"unsubscribe""#) })
                        return subscribes > 0 && subscribes == unsubscribes ? true : nil
                    }
                }
                await streams.disconnect()
                try await Self.expectEmpty(connection)
            }
            #expect(await transport.sessions.count == 20)
            for session in await transport.sessions { #expect(await session.isClosed) }
        }
    }
}
