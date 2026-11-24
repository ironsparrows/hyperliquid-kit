import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Testing

/// A WebSocket server on 127.0.0.1 that answers the client's first message with scripted frames and,
/// like Hyperliquid's server, never answers a close frame.
struct LoopbackWebSocketServer: Sendable {
    enum Script: Sendable {
        /// Sends these text frames after the client's first message.
        case send([String])
        /// Sends these text frames after the client's first message, then drops the connection without
        /// a close frame.
        case sendAndDrop([String])
    }

    /// The server's URL, such as `ws://127.0.0.1:52341/ws`.
    let url: URL
    /// Every text frame the server receives, in order.
    let received: AsyncStream<String>
    private let channel: any Channel
    private let finishReceived: @Sendable () -> Void

    /// Runs `body` with a server that follows `script`, and stops the server, and every connection it
    /// accepted, after.
    @discardableResult
    static func run<Result>(_ script: Script, _ body: (LoopbackWebSocketServer) async throws -> Result) async throws
        -> Result
    {
        let (received, continuation) = AsyncStream.makeStream(of: String.self)
        let accepted = NIOLockedValueBox<[any Channel]>([])
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                accepted.withLockedValue { $0.append(channel) }
                let upgrader = NIOWebSocketServerUpgrader(
                    maxFrameSize: 1 << 24,
                    shouldUpgrade: { channel, _ in channel.eventLoop.makeSucceededFuture(HTTPHeaders()) },
                    upgradePipelineHandler: { channel, _ in
                        channel.eventLoop.makeCompletedFuture {
                            try channel.pipeline.syncOperations.addHandler(Handler(script: script, received: continuation))
                        }
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
                )
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        let port = try #require(channel.localAddress?.port)
        let server = LoopbackWebSocketServer(
            url: URL(string: "ws://127.0.0.1:\(port)/ws")!, received: received, channel: channel,
            finishReceived: { continuation.finish() }
        )
        defer { server.finishReceived() }
        func stop() async {
            try? await channel.close()
            for child in accepted.withLockedValue({ $0 }) { try? await child.close() }
        }
        do {
            let result = try await body(server)
            await stop()
            return result
        } catch {
            await stop()
            throw error
        }
    }
}

private final class Handler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let script: LoopbackWebSocketServer.Script
    private let received: AsyncStream<String>.Continuation
    private var answered = false

    init(script: LoopbackWebSocketServer.Script, received: AsyncStream<String>.Continuation) {
        self.script = script
        self.received = received
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        // A close frame gets no answer, as from Hyperliquid's server.
        guard frame.opcode == .text else { return }
        var payload = frame.unmaskedData
        received.yield(payload.readString(length: payload.readableBytes) ?? "")
        guard !answered else { return }
        answered = true
        let (texts, drop) =
            switch script {
            case .send(let texts): (texts, false)
            case .sendAndDrop(let texts): (texts, true)
            }
        for text in texts {
            let frame = WebSocketFrame(fin: true, opcode: .text, data: context.channel.allocator.buffer(string: text))
            context.write(wrapOutboundOut(frame), promise: nil)
        }
        context.flush()
        if drop { context.close(promise: nil) }
    }
}
