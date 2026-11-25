import Foundation
import NIOCore
import Testing

@testable import HyperliquidKit

// Real WebSocket connections to a local server, through WebSocketKit.
extension HyperliquidKitTests {
    @Suite("Loopback WebSocket", .timeLimit(.minutes(1)))
    struct LoopbackWebSocketTests {
        @Test func `a 40 KB frame and hundreds of frames arrive whole and in order`() async throws {
            let large = #"{"channel":"x","data":""# + String(repeating: "a", count: 40_000) + #""}"#
            let numbered = (0..<500).map { #"{"n":\#($0)}"# }
            try await LoopbackWebSocketServer.run(.send([large] + numbered)) { server in
                let session = try await WebSocketKitTransport().connect(to: server.url)
                try await session.send(#"{"method":"ping"}"#)
                var frames: [String] = []
                for await frame in session.frames {
                    frames.append(frame)
                    if frames.count == 501 { break }
                }
                #expect(frames == [large] + numbered)
                await session.close()
            }
        }

        @Test func `a server that drops the connection without a close frame ends the frames`() async throws {
            try await LoopbackWebSocketServer.run(.sendAndDrop([#"{"n":1}"#])) { server in
                let session = try await WebSocketKitTransport().connect(to: server.url)
                try await session.send("hello")
                var frames: [String] = []
                for await frame in session.frames { frames.append(frame) }
                #expect(frames == [#"{"n":1}"#])
            }
        }

        @Test func `closing returns and ends the frames although the server never answers the close`() async throws {
            try await LoopbackWebSocketServer.run(.send([])) { server in
                let session = try await WebSocketKitTransport().connect(to: server.url)
                try await session.send("hello")
                await session.close()
                for await _ in session.frames {}
            }
        }

        @Test func `a server that never upgrades the connection throws connection failed in time`() async throws {
            try await LoopbackServer.run(answering: .never) { server in
                var url = URLComponents(url: server.url, resolvingAgainstBaseURL: false)!
                url.scheme = "ws"
                await #expect {
                    _ = try await WebSocketKitTransport(connectTimeout: .milliseconds(200)).connect(to: url.url!)
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .connectionFailed
                }
            }
        }

        @Test func `a refused connection throws connection failed`() async throws {
            var url = URLComponents(url: try await LoopbackServer.unusedURL(), resolvingAgainstBaseURL: false)!
            url.scheme = "ws"
            await #expect {
                _ = try await WebSocketKitTransport(connectTimeout: .seconds(2)).connect(to: url.url!)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .connectionFailed
            }
        }

        @Test func `a stream connection subscribes and routes a push over a real socket`() async throws {
            let push = #"{"channel":"allMids","data":{"mids":{"BTC":"60000"}}}"#
            try await LoopbackWebSocketServer.run(.send([push])) { server in
                let connection = StreamConnection(
                    url: server.url, transport: WebSocketKitTransport(), directory: AssetDirectory(info: .test(FakeTransport()))
                )
                let streams = Streams(connection: connection)
                var mids = streams.mids().makeAsyncIterator()
                let first = try await mids.next()
                #expect(first == ["BTC": 60000])
                var received = server.received.makeAsyncIterator()
                #expect(await received.next() == #"{"method":"subscribe","subscription":{"type":"allMids"}}"#)
                await streams.disconnect()
            }
        }

        @Test func `subscriptions started and ended in a tight loop reach the server in a valid order`() async throws {
            let perpDexs = #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#
            try await LoopbackWebSocketServer.run(.send([])) { server in
                let connection = StreamConnection(
                    url: server.url, transport: WebSocketKitTransport(),
                    directory: AssetDirectory(info: .test(FakeTransport(json: perpDexs)))
                )
                let streams = Streams(connection: connection)
                for _ in 0..<200 {
                    let stream = Task { for try await _ in streams.mids() {} }
                    await Task.yield()
                    stream.cancel()
                }
                try await eventually {
                    let state = await connection.bookkeeping
                    return state == (0, 0, 0, 0, 0) ? true : nil
                }
                // A last subscription marks the end of the loop's messages.
                let marker = Task { for try await _ in streams.mids(dex: .named("xyz")) {} }
                var expectSubscribe = true
                for await message in server.received {
                    if message.contains(#""dex":"xyz""#) { break }
                    // Every message alternates: a subscribe, then its unsubscribe.
                    #expect(message.contains(#""method":"subscribe""#) == expectSubscribe, "\(message)")
                    expectSubscribe.toggle()
                }
                #expect(expectSubscribe)
                marker.cancel()
                await streams.disconnect()
            }
        }
    }
}
