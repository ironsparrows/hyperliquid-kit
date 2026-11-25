import AsyncHTTPClient
import Foundation
import HyperliquidKitCore
import NIOCore
import WebSocketKit

/// Connects with WebSocketKit.
///
/// Frames are handed on in the order they arrive: the handlers are WebSocketKit's synchronous ones,
/// registered as the connection opens, because its `async` handlers start a task per frame, which can
/// reorder them.
struct WebSocketKitTransport: WebSocketTransport {
    /// The largest frame read. Hyperliquid's frames reach about 40 KB, more than WebSocketKit's default
    /// of 16 KiB.
    var maximumFrameSize = 16 * 1024 * 1024

    /// How long connecting may take, including the TLS handshake and the WebSocket upgrade. A connection
    /// still opening when it passes is closed if it opens later; one that never opens is left to the
    /// network stack's own timeouts.
    var connectTimeout: TimeAmount = .seconds(10)

    func connect(to url: URL) async throws -> any WebSocketSession {
        let (frames, continuation) = AsyncStream.makeStream(of: String.self)
        let group = HTTPClient.defaultEventLoopGroup
        // WebSocketKit can report the connection open before it calls `onUpgrade`, so the socket arrives
        // through its own promise. The first of the socket, a failure and the timeout wins; completing a
        // promise again does nothing.
        let opened = group.any().makePromise(of: WebSocket.self)
        let timeout = opened.futureResult.eventLoop.scheduleTask(in: connectTimeout) {
            opened.fail(Hyperliquid.ClientError(.connectionFailed, message: "The stream connection didn't open in time"))
        }
        opened.futureResult.whenComplete { _ in timeout.cancel() }
        WebSocket.connect(to: url, configuration: .init(maxFrameSize: maximumFrameSize), on: group) { socket in
            socket.onText { _, text in continuation.yield(text) }
            socket.onClose.whenComplete { _ in continuation.finish() }
            opened.succeed(socket)
            // A socket that opens after the timeout is closed.
            opened.futureResult.whenFailure { _ in _ = socket.close() }
        }.whenFailure { opened.fail($0) }
        do {
            return Session(socket: try await opened.futureResult.get(), frames: frames, finish: { continuation.finish() })
        } catch let error as Hyperliquid.ClientError {
            continuation.finish()
            throw error
        } catch {
            continuation.finish()
            throw Hyperliquid.ClientError(.connectionFailed, underlyingError: error)
        }
    }

    private struct Session: WebSocketSession {
        let socket: WebSocket
        let frames: AsyncStream<String>
        let finish: @Sendable () -> Void

        /// Hands the frame to the socket before suspending, so frames sent one after another from one
        /// actor reach the wire in that order.
        nonisolated(nonsending) func send(_ text: String) async throws {
            let written = socket.eventLoop.makePromise(of: Void.self)
            socket.send(text, promise: written)
            do {
                try await written.futureResult.get()
            } catch {
                throw Hyperliquid.ClientError(.connectionClosed, underlyingError: error)
            }
        }

        func close() async {
            finish()
            // Completes once the close frame is written; the server then drops the connection.
            try? await socket.close()
        }
    }
}
