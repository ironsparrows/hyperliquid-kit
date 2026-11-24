import Foundation

/// Opens WebSocket connections.
///
/// The seam between ``StreamConnection`` and the network: ``WebSocketKitTransport`` connects over the
/// network, and tests substitute a fake that scripts the server's frames.
protocol WebSocketTransport: Sendable {
    /// Connects to `url`, or throws ``Hyperliquid/ClientError`` with
    /// ``Hyperliquid/ClientError/Reason/connectionFailed``.
    func connect(to url: URL) async throws -> any WebSocketSession
}

/// One open WebSocket connection.
protocol WebSocketSession: Sendable {
    /// Every text frame the server sends, in the order it sent them. Finishes when the connection
    /// closes, either side first.
    var frames: AsyncStream<String> { get }

    /// Sends a text frame. Throws ``Hyperliquid/ClientError`` with
    /// ``Hyperliquid/ClientError/Reason/connectionClosed`` when the connection is closed.
    ///
    /// Runs on the caller's actor until the frame is handed on, so frames one actor sends one after
    /// another reach the wire in that order.
    nonisolated(nonsending) func send(_ text: String) async throws

    /// Closes the connection and finishes ``frames`` at once, without waiting for the server to
    /// confirm: Hyperliquid's server drops the connection instead of answering the close.
    func close() async
}
