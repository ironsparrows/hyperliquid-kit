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
    /// - with ``ClientError/Reason/unknownCoin`` for a coin or perp DEX Hyperliquid doesn't list, or
    ///   ``ClientError/Reason/unsupportedMarket`` for a spot or outcome coin, checked before subscribing;
    /// - with ``ClientError/Reason/invalidRequest`` for an order book of a coin already streaming at
    ///   another precision: Hyperliquid's pushes don't say which precision they are for;
    /// - with the decoding error when a push can't be read;
    /// - without an error after ``disconnect()``, or when the client is released.
    ///
    /// Streams of state, such as a book or mids, keep only the latest push for a slow reader; streams of
    /// events, such as trades and candle updates, keep every push in order.
    public protocol StreamAPI: Sendable {
        /// The mid price of every market on a perp DEX; on the first perp DEX, markets that aren't
        /// perpetuals too. (`allMids`)
        ///
        /// Each element holds the mids of one push; a slow reader gets only the latest.
        func mids(dex: PerpDex) -> AsyncThrowingStream<[Coin: Decimal], any Error>

        /// A perpetual's book, at most 20 levels per side, pushed on blocks at least half a second
        /// apart; a slow reader gets only the latest. (`l2Book`)
        ///
        /// One precision of a coin's book streams at a time, because pushes don't say which precision
        /// they are for. After switching precision, by ending one stream and starting another, the
        /// first books can still be at the old one.
        func orderBook(_ coin: Coin, precision: OrderBook.Precision) -> AsyncThrowingStream<OrderBook, any Error>

        /// A perpetual's best bid and ask, pushed only on a block where they change; a slow reader gets
        /// only the latest. (`bbo`)
        func bestBidOffer(_ coin: Coin) -> AsyncThrowingStream<BestBidOffer, any Error>

        /// A perpetual's trades, each push a batch, every batch kept in order. The first batch after
        /// subscribing can hold recent trades from before it. (`trades`)
        func trades(_ coin: Coin) -> AsyncThrowingStream<[Trade], any Error>

        /// Updates of a perpetual's current candle, every update kept in order, so a candle's last
        /// update before the next one opens isn't lost. (`candle`)
        func candles(_ coin: Coin, interval: Candle.Interval) -> AsyncThrowingStream<Candle, any Error>

        /// A perpetual's market state: prices, funding and open interest; a slow reader gets only the
        /// latest. (`activeAssetCtx`)
        func assetContext(_ coin: Coin) -> AsyncThrowingStream<AssetContext, any Error>

        /// Closes the connection and ends every stream without an error.
        func disconnect() async
    }
}

// MARK: - Defaults

extension Hyperliquid.StreamAPI {
    public func mids() -> AsyncThrowingStream<[Hyperliquid.Coin: Decimal], any Error> {
        mids(dex: .first)
    }

    /// A perpetual's book at full precision.
    public func orderBook(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error> {
        orderBook(coin, precision: .full)
    }
}
