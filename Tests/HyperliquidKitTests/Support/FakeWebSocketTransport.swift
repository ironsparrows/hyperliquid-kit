import Foundation
import Testing
@testable import HyperliquidKit

/// Opens scripted connections and records them, in order.
actor FakeWebSocketTransport: WebSocketTransport {
    private(set) var sessions: [FakeWebSocketSession] = []
    /// When set, the next connection attempts throw this.
    var failure: (any Error)?

    func connect(to url: URL) async throws -> any WebSocketSession {
        if let failure { throw failure }
        let session = FakeWebSocketSession()
        sessions.append(session)
        return session
    }

    func fail(with error: (any Error)?) {
        failure = error
    }

    /// The latest connection, once one is open.
    func session() async throws -> FakeWebSocketSession {
        try await eventually { sessions.last }
    }
}

/// A connection whose server side the test drives.
actor FakeWebSocketSession: WebSocketSession {
    nonisolated let frames: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private(set) var sent: [String] = []
    private(set) var isClosed = false

    init() {
        (frames, continuation) = AsyncStream.makeStream(of: String.self)
    }

    func send(_ text: String) async throws {
        guard !isClosed else { throw Hyperliquid.ClientError(.connectionClosed) }
        sent.append(text)
    }

    func close() async {
        isClosed = true
        continuation.finish()
    }

    /// Sends a frame from the server.
    func push(_ text: String) {
        continuation.yield(text)
    }

    /// Drops the connection from the server's side, without a close frame.
    func drop() {
        isClosed = true
        continuation.finish()
    }

    /// The messages sent, once at least `count` were.
    func sent(atLeast count: Int) async throws -> [String] {
        try await eventually { sent.count >= count ? sent : nil }
    }
}

/// Waits for `value` to return something, checking every millisecond for up to 5 seconds.
@discardableResult
func eventually<Value>(_ value: () async throws -> Value?) async throws -> Value {
    for _ in 0..<5000 {
        if let result = try await value() { return result }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("A condition wasn't met in time")
    throw CancellationError()
}
