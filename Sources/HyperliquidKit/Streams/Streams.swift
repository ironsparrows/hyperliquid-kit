import Foundation
import HyperliquidKitCore

/// Live pushes over the client's ``StreamConnection``: the market streams in ``MarketStreams``, the
/// account streams in ``AccountStreams``.
struct Streams: Hyperliquid.StreamAPI {
    let connection: StreamConnection
    let market: MarketStreams
    let account: AccountStreams

    /// - Parameters:
    ///   - connection: The connection every stream shares.
    ///   - account: The account that account streams given no user stream.
    init(connection: StreamConnection, account: Hyperliquid.Address? = nil) {
        self.connection = connection
        market = MarketStreams(connection: connection)
        self.account = AccountStreams(connection: connection, account: account)
    }

    // MARK: Markets

    func mids(dex: Hyperliquid.PerpDex) -> AsyncThrowingStream<[Hyperliquid.Coin: Decimal], any Error> {
        market.mids(dex: dex)
    }

    func orderBook(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision)
        -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error>
    {
        market.orderBook(coin, precision: precision)
    }

    func bestBidOffer(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.BestBidOffer, any Error> {
        market.bestBidOffer(coin)
    }

    func trades(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<[Hyperliquid.Trade], any Error> {
        market.trades(coin)
    }

    func candles(_ coin: Hyperliquid.Coin, interval: Hyperliquid.Candle.Interval)
        -> AsyncThrowingStream<Hyperliquid.Candle, any Error>
    {
        market.candles(coin, interval: interval)
    }

    func assetContext(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.AssetContext, any Error> {
        market.assetContext(coin)
    }

    // MARK: Compressed feeds

    func orderBookUpdates(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision)
        -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error>
    {
        market.orderBookUpdates(coin, precision: precision)
    }

    func prices() -> AsyncThrowingStream<[Hyperliquid.Coin: Hyperliquid.MarketPrices], any Error> {
        market.prices()
    }

    func assetContexts() -> AsyncThrowingStream<[Hyperliquid.Coin: Hyperliquid.AssetContext], any Error> {
        market.assetContexts()
    }

    // MARK: Account

    func orderUpdates(for user: Hyperliquid.Address?) -> AsyncThrowingStream<Hyperliquid.HistoricalOrder, any Error> {
        account.orderUpdates(for: user)
    }

    func fills(aggregateByTime: Bool, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.Fill>, any Error>
    {
        account.fills(aggregateByTime: aggregateByTime, for: user)
    }

    func events(for user: Hyperliquid.Address?) -> AsyncThrowingStream<Hyperliquid.UserEvent, any Error> {
        account.events(for: user)
    }

    func fundingPayments(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.FundingPayment>, any Error>
    {
        account.fundingPayments(for: user)
    }

    func ledger(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.LedgerUpdate>, any Error>
    {
        account.ledger(for: user)
    }

    func perpetualState(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.PerpetualState, any Error>
    {
        account.perpetualState(dex: dex, for: user)
    }

    func pendingOrders(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<[Hyperliquid.Order], any Error>
    {
        account.pendingOrders(dex: dex, for: user)
    }

    func tradingLimits(_ coin: Hyperliquid.Coin, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.TradingLimits, any Error>
    {
        account.tradingLimits(coin, for: user)
    }

    func balances(for user: Hyperliquid.Address?) -> AsyncThrowingStream<[Hyperliquid.Balance], any Error> {
        account.balances(for: user)
    }

    func notifications(for user: Hyperliquid.Address?) -> AsyncThrowingStream<String, any Error> {
        account.notifications(for: user)
    }

    func twapStates(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<[Hyperliquid.TwapID: Hyperliquid.Twap], any Error>
    {
        account.twapStates(dex: dex, for: user)
    }

    func twapSliceFills(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.TwapSliceFill>, any Error>
    {
        account.twapSliceFills(for: user)
    }

    func twapHistory(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.TwapHistoryEntry>, any Error>
    {
        account.twapHistory(for: user)
    }

    // MARK: Connection

    func disconnect() async {
        await connection.disconnect()
    }
}
