import Foundation
import HyperliquidKitCore

/// An account's orders and fills, read from `/info`.
struct OrderRequests: Hyperliquid.OrderAPI {
    let info: InfoClient
    /// The account a read uses when it is given none.
    let account: Hyperliquid.Address?

    // MARK: Orders

    func pending(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?) async throws -> [Hyperliquid.Order] {
        try await info.send(.openOrders(try resolveAccount(user, default: account), dex: dex))
    }

    func pendingDetailed(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?) async throws
        -> [Hyperliquid.Order]
    {
        try await info.send(.frontendOpenOrders(try resolveAccount(user, default: account), dex: dex))
    }

    func status(_ order: Hyperliquid.OrderIdentifier, for user: Hyperliquid.Address?) async throws
        -> Hyperliquid.HistoricalOrder?
    {
        try await info.send(.orderStatus(try resolveAccount(user, default: account), order: order)).order
    }

    func history(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.HistoricalOrder] {
        try await info.send(.historicalOrders(try resolveAccount(user, default: account)))
    }

    // MARK: Fills

    func fills(aggregateByTime: Bool, for user: Hyperliquid.Address?) async throws -> [Hyperliquid.Fill] {
        try await info.send(.userFills(try resolveAccount(user, default: account), aggregateByTime: aggregateByTime))
    }

    func fills(from start: Date, to end: Date?, aggregateByTime: Bool, for user: Hyperliquid.Address?)
        async throws -> [Hyperliquid.Fill]
    {
        let user = try resolveAccount(user, default: account)
        return try await info.send(.userFillsByTime(user, from: start, to: end, aggregateByTime: aggregateByTime))
    }
}

// MARK: - Requests

extension InfoRequest where Response == [Hyperliquid.Order] {
    static func openOrders(_ user: Hyperliquid.Address, dex: Hyperliquid.PerpDex) -> Self {
        Self("openOrders", userAndDex(user, dex))
    }

    static func frontendOpenOrders(_ user: Hyperliquid.Address, dex: Hyperliquid.PerpDex) -> Self {
        Self("frontendOpenOrders", userAndDex(user, dex))
    }

    private static func userAndDex(_ user: Hyperliquid.Address, _ dex: Hyperliquid.PerpDex) -> [ActionValue.Entry] {
        [userParameter(user), .init(key: "dex", value: .string(dex.name))]
    }
}

extension InfoRequest where Response == OrderStatusResponse {
    /// `oid` is the order's ID as a number, or the client order ID as its hexadecimal text.
    static func orderStatus(_ user: Hyperliquid.Address, order: Hyperliquid.OrderIdentifier) -> Self {
        let oid: ActionValue =
            switch order {
            case .id(let id): .unsigned(id.rawValue)
            case .clientID(let id): .string(id.description)
            }
        return Self("orderStatus", [userParameter(user), .init(key: "oid", value: oid)])
    }
}

extension InfoRequest where Response == [Hyperliquid.HistoricalOrder] {
    static func historicalOrders(_ user: Hyperliquid.Address) -> Self {
        Self("historicalOrders", [userParameter(user)])
    }
}

extension InfoRequest where Response == [Hyperliquid.Fill] {
    /// `aggregateByTime` is sent only when it is true.
    static func userFills(_ user: Hyperliquid.Address, aggregateByTime: Bool) -> Self {
        Self("userFills", [userParameter(user)] + (aggregateByTime ? [.init(key: "aggregateByTime", value: true)] : []))
    }

    /// `endTime` (as `null` when there is none, which Hyperliquid reads as now) and `aggregateByTime`
    /// are always sent.
    static func userFillsByTime(_ user: Hyperliquid.Address, from start: Date, to end: Date?, aggregateByTime: Bool)
        -> Self
    {
        Self(
            "userFillsByTime",
            [
                userParameter(user), .init(key: "startTime", value: .signed(start.wireMilliseconds)),
                .init(key: "endTime", value: end.map { .signed($0.wireMilliseconds) } ?? .null),
                .init(key: "aggregateByTime", value: .bool(aggregateByTime)),
            ]
        )
    }
}
