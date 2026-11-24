public import Foundation

extension Hyperliquid {
    /// An account's orders and fills, and the actions that place, change and cancel orders.
    ///
    /// Reached through ``API/order``. Reads take the account's address in `user` as ``AccountAPI``
    /// does: `nil` means the client's account, and without one the read throws
    /// ``ClientError/Reason/missingAccount`` before anything is sent. Results include spot orders and
    /// fills; ``Coin/kind`` tells them apart.
    ///
    /// Actions are signed by the client's signer and throw ``ClientError/Reason/missingSigner`` without
    /// one, and ``ClientError/Reason/unsupportedMarket`` for a spot or outcome coin, before anything is
    /// sent. An action that fails on the network, that Hyperliquid rejects, or whose answer the client
    /// can't read carries its nonce in the error. Canceling the task throws `CancellationError`, which
    /// carries none: an action canceled after it was sent may still execute.
    public protocol OrderAPI: Sendable {
        // MARK: Orders

        /// The account's pending orders on a perp DEX; on the first perp DEX, spot orders too.
        /// (`openOrders`)
        func pending(dex: PerpDex, for user: Address?) async throws -> [Order]

        /// The account's pending orders with how they were placed: type, trigger and original size.
        /// (`frontendOpenOrders`)
        func pendingDetailed(dex: PerpDex, for user: Address?) async throws -> [Order]

        /// An order and its status, or `nil` when Hyperliquid doesn't know the order. (`orderStatus`)
        func status(_ order: OrderIdentifier, for user: Address?) async throws -> HistoricalOrder?

        /// The account's most recent orders with their statuses, at most 2000. (`historicalOrders`)
        func history(for user: Address?) async throws -> [HistoricalOrder]

        // MARK: Fills

        /// The account's most recent fills, at most 2000. (`userFills`)
        ///
        /// - Parameters:
        ///   - aggregateByTime: Combines the partial fills of a crossing order that matched several
        ///     resting orders.
        ///   - user: The account; `nil` for the client's.
        func fills(aggregateByTime: Bool, for user: Address?) async throws -> [Fill]

        /// The account's fills from `start` to `end`, or to now when `end` is `nil`. A response holds at
        /// most 2000 fills, and only the 10000 most recent are available. (`userFillsByTime`)
        ///
        /// - Parameters:
        ///   - start: The earliest fill time.
        ///   - end: The latest fill time, or `nil` for now.
        ///   - aggregateByTime: Combines the partial fills of a crossing order that matched several
        ///     resting orders.
        ///   - user: The account; `nil` for the client's.
        func fills(from start: Date, to end: Date?, aggregateByTime: Bool, for user: Address?) async throws -> [Fill]

        // MARK: Actions

        /// Places orders, signed by the client's signer. (`order`)
        ///
        /// Each order gets its own result: a rejected order doesn't throw. The call throws
        /// `actionRejected` when Hyperliquid rejects the whole batch, and `unexpectedResponse` when its
        /// answer can't be matched to the orders. An order whose price, size or trigger price has more
        /// than 8 decimals is rounded to 8 when that moves it by less than 1e-12, or leaves the same
        /// `Double`, as the Python SDK compares, which absorbs a floating-point literal's error; for
        /// large values that can move it by less than one `Double` step. Otherwise it throws
        /// ``ClientError/Reason/invalidRequest`` before anything is sent. A market order reads its
        /// coin's mid price first, once per perp DEX, and throws ``ClientError/Reason/noMidPrice``
        /// without one, or ``ClientError/Reason/invalidRequest`` for slippage below 0 or at 100 % or
        /// more.
        ///
        /// - Parameters:
        ///   - orders: The orders, sent as one action.
        ///   - grouping: How the orders relate, such as ``Grouping/standalone``.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        ///     An action rejected this way counts five times against the address's request limit.
        func place(_ orders: [OrderRequest], grouping: Grouping, expiresAfter: Date?) async throws -> [PlacementResult]

        /// Closes the account's position in `coin` with a reduce-only market order, or does nothing and
        /// returns no results when there is no position. (`order`)
        ///
        /// The position is read for the client's account: its vault, else its account, else its signer.
        ///
        /// - Parameters:
        ///   - coin: The perpetual whose position to close.
        ///   - size: How much to close; `nil` or zero closes the whole position.
        ///   - price: The price the slippage applies to; `nil` or zero uses the mid price.
        ///   - slippage: As for ``OrderRequest/market(_:_:size:price:slippage:clientID:)``.
        ///   - clientID: The app's ID for the closing order.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func close(
            _ coin: Coin, size: Decimal?, price: Decimal?, slippage: Slippage, clientID: ClientOrderID?, expiresAfter: Date?
        ) async throws -> [PlacementResult]

        /// Cancels orders by Hyperliquid's ID. (`cancel`)
        ///
        /// - Parameters:
        ///   - orders: The orders, each with its coin; each gets its own result.
        ///   - fast: Hyperliquid rejects a fast cancel of a trigger order.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func cancel(_ orders: [OrderReference], fast: Bool, expiresAfter: Date?) async throws -> [CancelResult]

        /// Cancels orders by the app's client order ID. (`cancelByCloid`)
        ///
        /// - Parameters:
        ///   - orders: The orders, each with its coin; each gets its own result.
        ///   - fast: Hyperliquid rejects a fast cancel of a trigger order.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func cancel(clientIDs orders: [ClientOrderReference], fast: Bool, expiresAfter: Date?) async throws
            -> [CancelResult]

        /// Replaces orders: each is canceled and its new version placed. (`batchModify`)
        ///
        /// A new version whose price, size or trigger price rounding to 8 decimals would change, or that is a market
        /// order, throws ``ClientError/Reason/invalidRequest`` before anything is sent.
        ///
        /// - Parameters:
        ///   - changes: Each order and its new version.
        ///   - alwaysPlace: Places the new version even when the cancel fails. Without it, the new
        ///     version must be a resting limit order (add-liquidity-only, or good-til-canceled that
        ///     wouldn't match at once, which Hyperliquid then rests as add-liquidity-only).
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func modify(_ changes: [OrderChange], alwaysPlace: Bool, expiresAfter: Date?) async throws -> [PlacementResult]

        /// Cancels all of the account's orders at `deadline`, at least 5 seconds ahead: a dead man's
        /// switch. Hyperliquid triggers it at most 10 times a day. (`scheduleCancel`)
        ///
        /// - Parameters:
        ///   - deadline: When to cancel, at least 5 seconds ahead.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func scheduleCancelAll(at deadline: Date, expiresAfter: Date?) async throws

        /// Removes the scheduled cancel. (`scheduleCancel` without a time)
        ///
        /// - Parameter expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func clearScheduledCancel(expiresAfter: Date?) async throws

        /// Marks `nonce` as used, so an action sent with it can't execute: the way to stop an action
        /// whose outcome is unknown after a timeout. (`noop`)
        ///
        /// - Parameters:
        ///   - nonce: The nonce of the action to stop, from the error it threw.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func invalidate(nonce: UInt64, expiresAfter: Date?) async throws
    }
}

// MARK: - Defaults

extension Hyperliquid.OrderAPI {
    public func pending(dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Order] {
        try await pending(dex: dex, for: nil)
    }

    /// An account's pending orders on the first perp DEX, spot orders included.
    public func pending(for user: Hyperliquid.Address? = nil) async throws -> [Hyperliquid.Order] {
        try await pending(dex: .first, for: user)
    }

    public func pendingDetailed(dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Order] {
        try await pendingDetailed(dex: dex, for: nil)
    }

    /// An account's detailed pending orders on the first perp DEX, spot orders included.
    public func pendingDetailed(for user: Hyperliquid.Address? = nil) async throws -> [Hyperliquid.Order] {
        try await pendingDetailed(dex: .first, for: user)
    }

    public func status(_ order: Hyperliquid.OrderIdentifier) async throws -> Hyperliquid.HistoricalOrder? {
        try await status(order, for: nil)
    }

    public func history() async throws -> [Hyperliquid.HistoricalOrder] {
        try await history(for: nil)
    }

    public func fills(aggregateByTime: Bool) async throws -> [Hyperliquid.Fill] {
        try await fills(aggregateByTime: aggregateByTime, for: nil)
    }

    /// An account's most recent fills, not aggregated.
    public func fills(for user: Hyperliquid.Address? = nil) async throws -> [Hyperliquid.Fill] {
        try await fills(aggregateByTime: false, for: user)
    }

    public func fills(from start: Date, to end: Date? = nil, aggregateByTime: Bool) async throws -> [Hyperliquid.Fill] {
        try await fills(from: start, to: end, aggregateByTime: aggregateByTime, for: nil)
    }

    /// An account's fills from `start` to `end`, or to now, not aggregated.
    public func fills(from start: Date, to end: Date? = nil, for user: Hyperliquid.Address? = nil) async throws
        -> [Hyperliquid.Fill]
    {
        try await fills(from: start, to: end, aggregateByTime: false, for: user)
    }

    // MARK: Actions

    public func place(
        _ orders: [Hyperliquid.OrderRequest], grouping: Hyperliquid.Grouping = .standalone
    ) async throws -> [Hyperliquid.PlacementResult] {
        try await place(orders, grouping: grouping, expiresAfter: nil)
    }

    public func close(
        _ coin: Hyperliquid.Coin, size: Decimal? = nil, price: Decimal? = nil, slippage: Hyperliquid.Slippage = .percent(5),
        clientID: Hyperliquid.ClientOrderID? = nil
    ) async throws -> [Hyperliquid.PlacementResult] {
        try await close(coin, size: size, price: price, slippage: slippage, clientID: clientID, expiresAfter: nil)
    }

    public func cancel(_ orders: [Hyperliquid.OrderReference], fast: Bool = false) async throws -> [Hyperliquid.CancelResult] {
        try await cancel(orders, fast: fast, expiresAfter: nil)
    }

    public func cancel(
        clientIDs orders: [Hyperliquid.ClientOrderReference], fast: Bool = false
    ) async throws -> [Hyperliquid.CancelResult] {
        try await cancel(clientIDs: orders, fast: fast, expiresAfter: nil)
    }

    public func modify(
        _ changes: [Hyperliquid.OrderChange], alwaysPlace: Bool = false
    ) async throws -> [Hyperliquid.PlacementResult] {
        try await modify(changes, alwaysPlace: alwaysPlace, expiresAfter: nil)
    }

    public func scheduleCancelAll(at deadline: Date) async throws {
        try await scheduleCancelAll(at: deadline, expiresAfter: nil)
    }

    public func clearScheduledCancel() async throws {
        try await clearScheduledCancel(expiresAfter: nil)
    }

    public func invalidate(nonce: UInt64) async throws {
        try await invalidate(nonce: nonce, expiresAfter: nil)
    }
}
