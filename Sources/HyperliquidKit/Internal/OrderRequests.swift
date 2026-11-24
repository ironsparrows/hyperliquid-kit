import Foundation
import HyperliquidKitCore

/// An account's orders and fills, read from `/info`, and its order actions, sent to `/exchange`.
struct OrderRequests: Hyperliquid.OrderAPI {
    let info: InfoClient
    let exchange: ExchangeClient
    let directory: AssetDirectory
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

// MARK: - Actions

extension OrderRequests {
    func place(_ orders: [Hyperliquid.OrderRequest], grouping: Hyperliquid.Grouping, expiresAfter: Date?) async throws
        -> [Hyperliquid.PlacementResult]
    {
        _ = try exchange.requireSigner()
        var mids = MidPrices(info: info)
        var wires: [ActionValue] = []
        for order in orders {
            wires.append(try await wire(order, mids: &mids))
        }
        let action: ActionValue = ["type": "order", "orders": .array(wires), "grouping": .string(grouping.name)]
        return try await exchange.perform(action, statusesFor: orders.count, expiresAfter: expiresAfter)
    }

    func close(
        _ coin: Hyperliquid.Coin, size: Decimal?, price: Decimal?, slippage: Hyperliquid.Slippage,
        clientID: Hyperliquid.ClientOrderID?, expiresAfter: Date?
    ) async throws -> [Hyperliquid.PlacementResult] {
        _ = try exchange.requireSigner()
        try check(slippage)
        _ = try await directory.asset(for: coin)
        let state = try await info.send(.clearinghouseState(try resolveAccount(nil, default: account), dex: coin.dex))
        guard let position = state.positions.first(where: { $0.coin == coin }) else { return [] }
        // As the official SDK, a size of zero closes the whole position.
        let size = size.flatMap { $0.isZero ? nil : $0 } ?? abs(position.size)
        let order = Hyperliquid.OrderRequest(
            side: position.size < 0 ? .buy : .sell, coin: coin, price: price, size: size, reduceOnly: true,
            clientID: clientID, kind: .market(slippage)
        )
        return try await place([order], grouping: .standalone, expiresAfter: expiresAfter)
    }

    func cancel(_ orders: [Hyperliquid.OrderReference], fast: Bool, expiresAfter: Date?) async throws
        -> [Hyperliquid.CancelResult]
    {
        _ = try exchange.requireSigner()
        var cancels: [ActionValue] = []
        for order in orders {
            let asset = try await directory.asset(for: order.coin).id
            cancels.append(["a": .unsigned(UInt64(asset)), "o": .unsigned(order.id.rawValue)])
        }
        return try await exchange.perform(
            cancelAction("cancel", cancels, fast: fast), statusesFor: orders.count, expiresAfter: expiresAfter
        )
    }

    func cancel(clientIDs orders: [Hyperliquid.ClientOrderReference], fast: Bool, expiresAfter: Date?) async throws
        -> [Hyperliquid.CancelResult]
    {
        _ = try exchange.requireSigner()
        var cancels: [ActionValue] = []
        for order in orders {
            let asset = try await directory.asset(for: order.coin).id
            cancels.append(["asset": .unsigned(UInt64(asset)), "cloid": .string(order.clientID.description)])
        }
        return try await exchange.perform(
            cancelAction("cancelByCloid", cancels, fast: fast), statusesFor: orders.count, expiresAfter: expiresAfter
        )
    }

    func modify(_ changes: [Hyperliquid.OrderChange], alwaysPlace: Bool, expiresAfter: Date?) async throws
        -> [Hyperliquid.PlacementResult]
    {
        _ = try exchange.requireSigner()
        if changes.contains(where: { if case .market = $0.newOrder.kind { true } else { false } }) {
            throw Hyperliquid.ClientError(.invalidRequest, message: "A modification can't be a market order")
        }
        var mids = MidPrices(info: info)
        var modifies: [ActionValue] = []
        for change in changes {
            let order: ActionValue =
                switch change.order {
                case .id(let id): .unsigned(id.rawValue)
                case .clientID(let clientID): .string(clientID.description)
                }
            modifies.append(["oid": order, "order": try await wire(change.newOrder, mids: &mids)])
        }
        var entries: [ActionValue.Entry] = [.init(key: "type", value: "batchModify"), .init(key: "modifies", value: .array(modifies))]
        // Hyperliquid rejects an action hashed with `a: false`, so the flag is sent only when set.
        if alwaysPlace { entries.append(.init(key: "a", value: true)) }
        return try await exchange.perform(.map(entries), statusesFor: changes.count, expiresAfter: expiresAfter)
    }

    func scheduleCancelAll(at deadline: Date, expiresAfter: Date?) async throws {
        try await exchange.perform(
            ["type": "scheduleCancel", "time": .unsigned(milliseconds(deadline))], expiresAfter: expiresAfter
        )
    }

    func clearScheduledCancel(expiresAfter: Date?) async throws {
        try await exchange.perform(["type": "scheduleCancel"], expiresAfter: expiresAfter)
    }

    func invalidate(nonce: UInt64, expiresAfter: Date?) async throws {
        try await exchange.perform(["type": "noop"], nonce: nonce, expiresAfter: expiresAfter)
    }

    /// An order as an action lists it: `a`, `b`, `p`, `s`, `r`, `t` and, with a client order ID, `c`.
    private func wire(_ order: Hyperliquid.OrderRequest, mids: inout MidPrices) async throws -> ActionValue {
        let asset = try await directory.asset(for: order.coin)
        let price: Decimal
        let type: ActionValue
        switch order.kind {
        case .limit(let timeInForce):
            price = try requirePrice(order)
            type = ["limit": ["tif": .string(timeInForce.rawValue)]]
        case .market(let slippage):
            // A market order is an immediate-or-cancel limit order at the slippage price.
            price = try await marketPrice(order, slippage: slippage, sizeDecimals: asset.sizeDecimals, mids: &mids)
            type = ["limit": ["tif": .string(Hyperliquid.TimeInForce.immediateOrCancel.rawValue)]]
        case .trigger(let kind, let triggerPrice, let isMarket):
            price = try requirePrice(order)
            let trigger: ActionValue = [
                "isMarket": .bool(isMarket), "triggerPx": .string(try wireNumber(triggerPrice, "trigger price")),
                "tpsl": .string(kind.rawValue),
            ]
            type = ["trigger": trigger]
        }
        var entries: [ActionValue.Entry] = [
            .init(key: "a", value: .unsigned(UInt64(asset.id))),
            .init(key: "b", value: .bool(order.side == .buy)),
            .init(key: "p", value: .string(try wireNumber(price, "price"))),
            .init(key: "s", value: .string(try wireNumber(order.size, "size"))),
            .init(key: "r", value: .bool(order.reduceOnly)),
            .init(key: "t", value: type),
        ]
        if let clientID = order.clientID { entries.append(.init(key: "c", value: .string(clientID.description))) }
        return .map(entries)
    }

    /// The limit price of a limit or trigger order, which their builders always set.
    private func requirePrice(_ order: Hyperliquid.OrderRequest) throws(Hyperliquid.ClientError) -> Decimal {
        guard let price = order.price else { throw Hyperliquid.ClientError(.invalidRequest, message: "The order has no price") }
        return price
    }

    /// The limit price of a market order: its price, or the coin's mid price, moved by the slippage.
    private func marketPrice(
        _ order: Hyperliquid.OrderRequest, slippage: Hyperliquid.Slippage, sizeDecimals: Int, mids: inout MidPrices
    ) async throws -> Decimal {
        try check(slippage)
        let base: Decimal
        // As the official SDK, a price of zero counts as none.
        if let price = order.price, !price.isZero {
            base = price
        } else {
            guard let mid = try await mids.price(of: order.coin) else {
                throw Hyperliquid.ClientError(.noMidPrice, message: order.coin.name)
            }
            base = mid
        }
        return slippagePrice(base, isBuy: order.side == .buy, slippage: slippage.fraction, sizeDecimals: sizeDecimals)
    }

    /// Throws for slippage below 0 or at 100 % or more.
    private func check(_ slippage: Hyperliquid.Slippage) throws(Hyperliquid.ClientError) {
        guard slippage.fraction >= 0, slippage.fraction < 1 else {
            throw Hyperliquid.ClientError(
                .invalidRequest, message: "Slippage of \(slippage.fraction * 100) % must be at least 0 % and below 100 %"
            )
        }
    }

    /// A cancel action; Hyperliquid rejects one hashed with `f: false`, so the flag is sent only when set.
    private func cancelAction(_ type: String, _ cancels: [ActionValue], fast: Bool) -> ActionValue {
        var entries: [ActionValue.Entry] = [.init(key: "type", value: .string(type)), .init(key: "cancels", value: .array(cancels))]
        if fast { entries.append(.init(key: "f", value: true)) }
        return .map(entries)
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

/// Mid prices read once per perp DEX during one action.
private struct MidPrices {
    let info: InfoClient
    private var byDex: [Hyperliquid.PerpDex: [Hyperliquid.Coin: Decimal]] = [:]

    init(info: InfoClient) {
        self.info = info
    }

    mutating func price(of coin: Hyperliquid.Coin) async throws -> Decimal? {
        if let mids = byDex[coin.dex] { return mids[coin] }
        let mids = try await info.send(.allMids(coin.dex)).mapValues(\.value)
        byDex[coin.dex] = mids
        return mids[coin]
    }
}
