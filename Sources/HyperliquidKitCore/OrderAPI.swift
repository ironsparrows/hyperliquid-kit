public import Foundation

extension Hyperliquid {
    /// An account's orders and fills.
    ///
    /// Reached through ``API/order``. Reads take the account's address in `user` as ``AccountAPI``
    /// does: `nil` means the client's account, and without one the read throws
    /// ``ClientError/Reason/missingAccount`` before anything is sent. Results include spot orders and
    /// fills; ``Coin/kind`` tells them apart.
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
        /// - Parameter aggregateByTime: Combines the partial fills of a crossing order that matched
        ///   several resting orders.
        func fills(aggregateByTime: Bool, for user: Address?) async throws -> [Fill]

        /// The account's fills from `start` to `end`, or to now when `end` is `nil`. A response holds at
        /// most 2000 fills, and only the 10000 most recent are available. (`userFillsByTime`)
        ///
        /// - Parameter aggregateByTime: Combines the partial fills of a crossing order that matched
        ///   several resting orders.
        func fills(from start: Date, to end: Date?, aggregateByTime: Bool, for user: Address?) async throws -> [Fill]
    }

    /// An order named by Hyperliquid's ID or by the app's client order ID.
    public enum OrderIdentifier: Hashable, Sendable {
        case id(OrderID)
        case clientID(ClientOrderID)
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
}
