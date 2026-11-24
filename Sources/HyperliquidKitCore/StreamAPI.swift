public import Foundation

extension Hyperliquid {
    /// Live pushes from Hyperliquid over one shared WebSocket connection.
    ///
    /// Reached through ``API/stream``. The connection opens with the first stream and stays open until
    /// ``disconnect()`` or the client is released. Streams of the same subscription share it: the
    /// subscription is sent for the first and removed when the last one ends.
    ///
    /// Account streams take the account's address in `user` as ``AccountAPI`` does: `nil` means the
    /// client's account. Pass the account's own address, not an API wallet's, which streams as an
    /// empty account. Order updates, events and notifications stream one account at a time, since
    /// their pushes don't say which account they are for. Unsubscribing isn't confirmed, so right
    /// after the last stream of one account ends, pushes for it still on their way can reach a stream
    /// just started for another account.
    ///
    /// A stream ends:
    /// - with ``ClientError/Reason/connectionClosed`` when the connection drops; every stream on it
    ///   ends, and nothing reconnects: start the streams again to subscribe on a new connection;
    /// - with ``ClientError/Reason/connectionFailed`` when the connection can't open;
    /// - with ``ClientError/Reason/unknownCoin`` for a coin or perp DEX Hyperliquid doesn't list, or
    ///   ``ClientError/Reason/unsupportedMarket`` for a spot or outcome coin, checked before subscribing;
    /// - with ``ClientError/Reason/missingAccount`` for an account stream given no `user` on a client
    ///   without an account, before subscribing;
    /// - with ``ClientError/Reason/invalidRequest`` for a second stream of book updates, prices or
    ///   asset contexts while one lasts: their pushes build on the snapshot that only the first stream
    ///   gets;
    /// - with ``ClientError/Reason/invalidRequest`` for an order book of a coin already streaming at
    ///   another precision, fills already streaming with the other `aggregateByTime`, or order
    ///   updates, events or notifications already streaming for another account: Hyperliquid's
    ///   pushes don't say which of them they are for. Streams started at the same moment subscribe in
    ///   no fixed order, so which of two such streams is refused isn't fixed either;
    /// - with the decoding error when a push can't be read;
    /// - without an error after ``disconnect()``, or when the client is released.
    ///
    /// Streams of state, such as a book, mids or an account's positions, keep only the latest push
    /// for a slow reader; streams of events, such as trades, candle updates and fills, keep every
    /// push in order. Streams that start with a snapshot of recent events yield a ``Batch`` per push,
    /// which says whether it is that snapshot. Only the stream that starts a subscription gets its
    /// snapshot; a stream that joins one already streaming gets the pushes from then on. A stream that
    /// subscribes again right after another of its kind ended can first get pushes sent for the earlier
    /// subscription, such as its snapshot.
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

        // MARK: Compressed market feeds

        /// A perpetual's book, at most 20 levels per side, kept up to date from Hyperliquid's diffs:
        /// the whole book after the snapshot sent on subscribing and after each diff; every diff is
        /// applied, and a slow reader gets only the latest book. (`l2`)
        ///
        /// Diffs don't carry order counts, so a level a diff adds or changes has no
        /// ``OrderBook/Level/orderCount``. A diff that doesn't fit the book ends the stream with
        /// ``HyperliquidError`` of kind `unexpectedResponse`, and one that can't be read with the
        /// decoding error; start the stream again for a new snapshot. One stream of a coin's book
        /// updates runs at a time.
        func orderBookUpdates(_ coin: Coin, precision: OrderBook.Precision) -> AsyncThrowingStream<OrderBook, any Error>

        /// The mark and mid price of every market Hyperliquid lists, spot and outcome markets included,
        /// merged from Hyperliquid's updates: all of them in each element; every update is merged,
        /// and a slow reader gets only the latest. (`fastAssetCtxs`)
        ///
        /// The first push after subscribing holds every market. One stream runs at a time. When a
        /// stream ends and another starts on the same connection, the new one's first element can
        /// lack markets, from updates sent before its first push.
        func prices() -> AsyncThrowingStream<[Coin: MarketPrices], any Error>

        /// The market state of every perpetual on every perp DEX, merged from Hyperliquid's updates:
        /// all of them in each element; every update is merged, and a slow reader gets only the
        /// latest. (`pac`)
        ///
        /// These pushes carry no premium or impact prices, so those are `nil`. Pushes name perpetuals
        /// by their position in their perp DEX's list, which the client loads in the background when a
        /// perp DEX first appears: a perpetual appears once Hyperliquid has sent all of its required
        /// fields and its perp DEX's list has loaded. A perp DEX whose list fails to load stays out
        /// until the stream starts again, and perpetuals listed after it loaded are left out. A perp
        /// DEX deployed after the client read the list of perp DEXs can appear here although other
        /// requests for it throw ``ClientError/Reason/unknownCoin``. One stream runs at a time; as
        /// with ``prices()``, a stream started right after another ends can begin incomplete.
        func assetContexts() -> AsyncThrowingStream<[Coin: AssetContext], any Error>

        // MARK: Account

        /// Changes to the account's orders: each placement, fill, cancel or rejection, every update
        /// kept in order. Whether Hyperliquid first sends the orders pending when subscribing isn't
        /// documented; read them with ``OrderAPI/pendingDetailed(dex:for:)`` or
        /// ``pendingOrders(dex:for:)``. (`orderUpdates`)
        func orderUpdates(for user: Address?) -> AsyncThrowingStream<HistoricalOrder, any Error>

        /// The account's fills: a snapshot of recent fills, then new ones, every batch kept in order.
        /// (`userFills`)
        ///
        /// After switching `aggregateByTime`, by ending one stream and starting another, the first
        /// batches can still be in the old form.
        ///
        /// - Parameters:
        ///   - aggregateByTime: Combines the partial fills of a crossing order that matched several
        ///     resting orders.
        ///   - user: The account; `nil` for the client's.
        func fills(aggregateByTime: Bool, for user: Address?) -> AsyncThrowingStream<Batch<Fill>, any Error>

        /// The account's fills, funding payments, liquidations and the orders Hyperliquid canceled,
        /// every event kept in order, with no snapshot. An event of a kind ``UserEvent`` doesn't
        /// model arrives as ``UserEvent/unknown(kind:)``; a push holding several events yields each.
        /// (`userEvents`)
        func events(for user: Address?) -> AsyncThrowingStream<UserEvent, any Error>

        /// The account's funding payments: a snapshot of recent payments, then each hour's, every batch
        /// kept in order. (`userFundings`)
        func fundingPayments(for user: Address?) -> AsyncThrowingStream<Batch<FundingPayment>, any Error>

        /// Changes to the account's balances other than funding: a snapshot of recent ones, then new
        /// ones, every batch kept in order. (`userNonFundingLedgerUpdates`)
        func ledger(for user: Address?) -> AsyncThrowingStream<Batch<LedgerUpdate>, any Error>

        /// The account's positions and margin on a perp DEX, pushed on subscribing and again every few
        /// seconds, changed or not; a slow reader gets only the latest. (`clearinghouseState`)
        func perpetualState(dex: PerpDex, for user: Address?) -> AsyncThrowingStream<PerpetualState, any Error>

        /// The account's pending orders on a perp DEX with how they were placed, all of them in each
        /// push, pushed on subscribing and again every few seconds; a slow reader gets only the
        /// latest. (`openOrders`)
        func pendingOrders(dex: PerpDex, for user: Address?) -> AsyncThrowingStream<[Order], any Error>

        /// What the account can trade in a perpetual at its current leverage, pushed on subscribing
        /// and again every few seconds; a slow reader gets only the latest. (`activeAssetData`)
        func tradingLimits(_ coin: Coin, for user: Address?) -> AsyncThrowingStream<TradingLimits, any Error>

        /// The account's token balances, all of them in each push, pushed on subscribing and again
        /// every few seconds; a slow reader gets only the latest. (`spotState`)
        func balances(for user: Address?) -> AsyncThrowingStream<[Balance], any Error>

        /// Hyperliquid's notifications for the account as display text, such as
        /// `"Resting order filled: Sold 6.7 HYPE at $61.819"`, every one kept in order.
        /// (`notification`)
        func notifications(for user: Address?) -> AsyncThrowingStream<String, any Error>

        /// The account's running TWAP orders on a perp DEX by ID, all of them in each push, pushed on
        /// subscribing and again every few seconds; a slow reader gets only the latest. (`twapStates`)
        func twapStates(dex: PerpDex, for user: Address?) -> AsyncThrowingStream<[TwapID: Twap], any Error>

        /// Fills of the account's TWAP slices: a snapshot of recent ones, then new ones, every batch
        /// kept in order. (`userTwapSliceFills`)
        func twapSliceFills(for user: Address?) -> AsyncThrowingStream<Batch<TwapSliceFill>, any Error>

        /// The account's TWAP orders and the statuses they reach: a snapshot of recent ones, then new
        /// ones, every batch kept in order. (`userTwapHistory`)
        func twapHistory(for user: Address?) -> AsyncThrowingStream<Batch<TwapHistoryEntry>, any Error>

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

    /// A perpetual's book at full precision, kept up to date from Hyperliquid's diffs.
    public func orderBookUpdates(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error> {
        orderBookUpdates(coin, precision: .full)
    }

    // MARK: Account

    public func orderUpdates() -> AsyncThrowingStream<Hyperliquid.HistoricalOrder, any Error> {
        orderUpdates(for: nil)
    }

    public func fills(aggregateByTime: Bool) -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.Fill>, any Error> {
        fills(aggregateByTime: aggregateByTime, for: nil)
    }

    /// An account's fills, not aggregated.
    public func fills(for user: Hyperliquid.Address? = nil)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.Fill>, any Error>
    {
        fills(aggregateByTime: false, for: user)
    }

    public func events() -> AsyncThrowingStream<Hyperliquid.UserEvent, any Error> {
        events(for: nil)
    }

    public func fundingPayments() -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.FundingPayment>, any Error> {
        fundingPayments(for: nil)
    }

    public func ledger() -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.LedgerUpdate>, any Error> {
        ledger(for: nil)
    }

    public func perpetualState(dex: Hyperliquid.PerpDex) -> AsyncThrowingStream<Hyperliquid.PerpetualState, any Error> {
        perpetualState(dex: dex, for: nil)
    }

    /// An account's positions and margin on the first perp DEX.
    public func perpetualState(for user: Hyperliquid.Address? = nil)
        -> AsyncThrowingStream<Hyperliquid.PerpetualState, any Error>
    {
        perpetualState(dex: .first, for: user)
    }

    public func pendingOrders(dex: Hyperliquid.PerpDex) -> AsyncThrowingStream<[Hyperliquid.Order], any Error> {
        pendingOrders(dex: dex, for: nil)
    }

    /// An account's pending orders on the first perp DEX.
    public func pendingOrders(for user: Hyperliquid.Address? = nil)
        -> AsyncThrowingStream<[Hyperliquid.Order], any Error>
    {
        pendingOrders(dex: .first, for: user)
    }

    public func tradingLimits(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.TradingLimits, any Error> {
        tradingLimits(coin, for: nil)
    }

    public func balances() -> AsyncThrowingStream<[Hyperliquid.Balance], any Error> {
        balances(for: nil)
    }

    public func notifications() -> AsyncThrowingStream<String, any Error> {
        notifications(for: nil)
    }

    public func twapStates(dex: Hyperliquid.PerpDex)
        -> AsyncThrowingStream<[Hyperliquid.TwapID: Hyperliquid.Twap], any Error>
    {
        twapStates(dex: dex, for: nil)
    }

    /// An account's running TWAP orders on the first perp DEX.
    public func twapStates(for user: Hyperliquid.Address? = nil)
        -> AsyncThrowingStream<[Hyperliquid.TwapID: Hyperliquid.Twap], any Error>
    {
        twapStates(dex: .first, for: user)
    }

    public func twapSliceFills() -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.TwapSliceFill>, any Error> {
        twapSliceFills(for: nil)
    }

    public func twapHistory() -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.TwapHistoryEntry>, any Error> {
        twapHistory(for: nil)
    }
}
