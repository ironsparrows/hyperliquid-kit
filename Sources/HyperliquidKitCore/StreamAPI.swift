public import Foundation

extension Hyperliquid {
    /// Live pushes from Hyperliquid over one shared WebSocket connection.
    ///
    /// Reached through ``API/stream``. The connection opens with the first stream and stays open until
    /// ``disconnect()`` or the client is released. Streams of the same subscription share it: the
    /// subscription is sent for the first and removed when the last one ends.
    ///
    /// A stream ends:
    /// - with ``ClientError/Reason/connectionClosed`` when the connection drops; every stream on it
    ///   ends, and nothing reconnects: start the streams again to subscribe on a new connection;
    /// - with ``ClientError/Reason/connectionFailed`` when the connection can't open;
    /// - with ``ClientError/Reason/unknownCoin`` for a perp DEX Hyperliquid doesn't list, checked before
    ///   subscribing;
    /// - with the decoding error when a push can't be read;
    /// - without an error after ``disconnect()``, or when the client is released.
    public protocol StreamAPI: Sendable {
        /// The mid price of every market on a perp DEX; on the first perp DEX, markets that aren't
        /// perpetuals too. (`allMids`)
        ///
        /// Each element holds the mids of one push; a slow consumer gets only the latest.
        func mids(dex: PerpDex) -> AsyncThrowingStream<[Coin: Decimal], any Error>

        /// Closes the connection and ends every stream without an error.
        func disconnect() async
    }
}

// MARK: - Defaults

extension Hyperliquid.StreamAPI {
    public func mids() -> AsyncThrowingStream<[Hyperliquid.Coin: Decimal], any Error> {
        mids(dex: .first)
    }
}
