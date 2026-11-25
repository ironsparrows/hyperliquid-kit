import Foundation
import HyperliquidKitCore

/// The account streams over the client's ``StreamConnection``: each subscribes for `user`, else the
/// client's account, and ends with `missingAccount` before subscribing when there is neither.
struct AccountStreams: Sendable {
    let connection: StreamConnection
    /// The account that account streams given no user stream.
    let account: Hyperliquid.Address?

    // MARK: Account

    func orderUpdates(for user: Hyperliquid.Address?) -> AsyncThrowingStream<Hyperliquid.HistoricalOrder, any Error> {
        stream(
            for: user, { .userless("orderUpdates", channel: "orderUpdates", $0) }, buffering: .all,
            decodeEach: { data in
                try StreamConnection.payload([Hyperliquid.HistoricalOrder].self, of: data)
            })
    }

    func fills(aggregateByTime: Bool, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.Fill>, any Error>
    {
        stream(
            for: user, { .fills($0, aggregateByTime: aggregateByTime) }, buffering: .all,
            decodeEach: { data in
                [try StreamConnection.payload(BatchPush<Hyperliquid.Fill, Fills>.self, of: data).batch]
            })
    }

    func events(for user: Hyperliquid.Address?) -> AsyncThrowingStream<Hyperliquid.UserEvent, any Error> {
        // Events arrive on channel `user`.
        stream(
            for: user, { .userless("userEvents", channel: "user", $0) }, buffering: .all,
            decodeEach: { data in
                try StreamConnection.payload(EventsPush.self, of: data).events
            })
    }

    func fundingPayments(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.FundingPayment>, any Error>
    {
        stream(
            for: user, { .user("userFundings", $0) }, buffering: .all,
            decodeEach: { data in
                [try StreamConnection.payload(BatchPush<Hyperliquid.FundingPayment, Fundings>.self, of: data).batch]
            })
    }

    func ledger(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.LedgerUpdate>, any Error>
    {
        stream(
            for: user, { .user("userNonFundingLedgerUpdates", $0) }, buffering: .all,
            decodeEach: { data in
                [try StreamConnection.payload(BatchPush<Hyperliquid.LedgerUpdate, LedgerUpdates>.self, of: data).batch]
            })
    }

    func perpetualState(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.PerpetualState, any Error>
    {
        stream(
            for: user, { .userOnDex("clearinghouseState", $0, dex: dex) }, buffering: .latest,
            decodeEach: { data in
                [try StreamConnection.payload(PerpetualStatePush.self, of: data).clearinghouseState]
            })
    }

    func pendingOrders(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<[Hyperliquid.Order], any Error>
    {
        stream(
            for: user, { .userOnDex("openOrders", $0, dex: dex) }, buffering: .latest,
            decodeEach: { data in
                [try StreamConnection.payload(PendingOrdersPush.self, of: data).orders]
            })
    }

    func tradingLimits(_ coin: Hyperliquid.Coin, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.TradingLimits, any Error>
    {
        stream(
            for: user, { .activeAssetData(coin, $0) }, buffering: .latest,
            decodeEach: { data in
                [try StreamConnection.payload(Hyperliquid.TradingLimits.self, of: data)]
            })
    }

    func balances(for user: Hyperliquid.Address?) -> AsyncThrowingStream<[Hyperliquid.Balance], any Error> {
        stream(
            for: user, { .user("spotState", $0) }, buffering: .latest,
            decodeEach: { data in
                [try StreamConnection.payload(BalancesPush.self, of: data).spotState.balances]
            })
    }

    func notifications(for user: Hyperliquid.Address?) -> AsyncThrowingStream<String, any Error> {
        stream(
            for: user, { .userless("notification", channel: "notification", $0) }, buffering: .all,
            decodeEach: { data in
                [try StreamConnection.payload(NotificationPush.self, of: data).notification]
            })
    }

    func twapStates(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<[Hyperliquid.TwapID: Hyperliquid.Twap], any Error>
    {
        stream(
            for: user, { .userOnDex("twapStates", $0, dex: dex) }, buffering: .latest,
            decodeEach: { data in
                [try StreamConnection.payload(TwapStatesPush.self, of: data).states]
            })
    }

    func twapSliceFills(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.TwapSliceFill>, any Error>
    {
        stream(
            for: user, { .user("userTwapSliceFills", $0) }, buffering: .all,
            decodeEach: { data in
                [try StreamConnection.payload(BatchPush<Hyperliquid.TwapSliceFill, TwapSliceFills>.self, of: data).batch]
            })
    }

    func twapHistory(for user: Hyperliquid.Address?)
        -> AsyncThrowingStream<Hyperliquid.Batch<Hyperliquid.TwapHistoryEntry>, any Error>
    {
        stream(
            for: user, { .user("userTwapHistory", $0) }, buffering: .all,
            decodeEach: { data in
                [try StreamConnection.payload(BatchPush<Hyperliquid.TwapHistoryEntry, TwapHistory>.self, of: data).batch]
            })
    }

    // MARK: Subscribing

    /// A stream of the elements each push holds, subscribed for `user`, else the client's account.
    private func stream<Element: Sendable>(
        for user: Hyperliquid.Address?, _ subscription: (Hyperliquid.Address) -> StreamConnection.Subscription,
        buffering: StreamConnection.Buffering, decodeEach: @escaping @Sendable (Data) throws -> [Element]
    ) -> AsyncThrowingStream<Element, any Error> {
        do {
            let user = try resolveAccount(user, default: account)
            return connection.stream(subscription(user), buffering: buffering, decodeEach: decodeEach)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }
}

// MARK: - Subscriptions

extension StreamConnection.Subscription {
    /// `{type, user}` for a channel whose pushes carry the user; they are routed by it.
    static func user(_ type: String, _ user: Hyperliquid.Address) -> Self {
        Self(
            topic: .init(channel: type, key: user.description),
            request: ["type": .string(type), "user": .string(user.description)]
        )
    }

    /// `{type, user}` for a channel whose pushes carry no user, so only one account streams on it.
    static func userless(_ type: String, channel: String, _ user: Hyperliquid.Address) -> Self {
        Self(
            topic: .init(channel: channel, key: ""), request: ["type": .string(type), "user": .string(user.description)],
            conflict: "\(type) is already streaming for another account: its pushes don't say which account they are for"
        )
    }

    /// `userFills`, with `aggregateByTime` only when it is true.
    static func fills(_ user: Hyperliquid.Address, aggregateByTime: Bool) -> Self {
        Self(
            topic: .init(channel: "userFills", key: user.description),
            request: .map(
                [.init(key: "type", value: "userFills"), .init(key: "user", value: .string(user.description))]
                    + (aggregateByTime ? [.init(key: "aggregateByTime", value: true)] : [])
            )
        )
    }

    /// `{type, user, dex}`, routed by both; a builder-deployed perp DEX is checked first.
    static func userOnDex(_ type: String, _ user: Hyperliquid.Address, dex: Hyperliquid.PerpDex) -> Self {
        Self(
            topic: .init(channel: type, key: "\(user),\(dex.name)"),
            request: ["type": .string(type), "user": .string(user.description), "dex": .string(dex.name)],
            dex: dex
        )
    }

    /// `activeAssetData` for a perpetual, routed by coin and user; the coin is checked first.
    static func activeAssetData(_ coin: Hyperliquid.Coin, _ user: Hyperliquid.Address) -> Self {
        Self(
            topic: .init(channel: "activeAssetData", key: "\(coin.name),\(user)"),
            request: ["type": "activeAssetData", "user": .string(user.description), "coin": .string(coin.name)],
            coin: coin
        )
    }
}

// MARK: - Wire

/// The data of a channel that starts with a snapshot: `{"isSnapshot"?: true, "user": …, <list>: […]}`,
/// where `List` names the list. Pushes after the snapshot leave out `isSnapshot`.
private struct BatchPush<Element: Decodable & Sendable, List: BatchList>: Decodable {
    let batch: Hyperliquid.Batch<Element>

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Field.self)
        batch = .init(
            isSnapshot: try container.decodeIfPresent(Bool.self, forKey: Field(stringValue: "isSnapshot")) ?? false,
            elements: try container.decode([Element].self, forKey: Field(stringValue: List.name))
        )
    }
}

/// The name of the list a snapshot channel's data holds.
private protocol BatchList {
    static var name: String { get }
}

private enum Fills: BatchList { static let name = "fills" }
private enum Fundings: BatchList { static let name = "fundings" }
private enum LedgerUpdates: BatchList { static let name = "nonFundingLedgerUpdates" }
private enum TwapSliceFills: BatchList { static let name = "twapSliceFills" }
private enum TwapHistory: BatchList { static let name = "history" }

/// `user` data: an object whose fields are events, normally one, each read as its own event.
private struct EventsPush: Decodable {
    let events: [Hyperliquid.UserEvent]

    init(from decoder: any Decoder) throws {
        events = try Hyperliquid.UserEvent.all(from: decoder)
    }
}

/// `clearinghouseState` data: `{"dex": …, "user": …, "clearinghouseState": …}`.
private struct PerpetualStatePush: Decodable {
    let clearinghouseState: Hyperliquid.PerpetualState
}

/// `openOrders` data: `{"dex": …, "user": …, "orders": […]}`.
private struct PendingOrdersPush: Decodable {
    let orders: [Hyperliquid.Order]
}

/// `spotState` data: `{"user": …, "spotState": {"balances": […]}}`.
private struct BalancesPush: Decodable {
    let spotState: SpotState
}

/// `notification` data: `{"notification": …}`.
private struct NotificationPush: Decodable {
    let notification: String
}

/// `twapStates` data: `{"dex": …, "user": …, "states": [[twapId, state], …]}`.
private struct TwapStatesPush: Decodable {
    let states: [Hyperliquid.TwapID: Hyperliquid.Twap]

    private enum CodingKeys: String, CodingKey {
        case states
    }

    private struct Entry: Decodable {
        let id: Hyperliquid.TwapID
        let twap: Hyperliquid.Twap

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            id = try pair.decode(Hyperliquid.TwapID.self)
            twap = try pair.decode(Hyperliquid.Twap.self)
        }
    }

    init(from decoder: any Decoder) throws {
        let entries = try decoder.container(keyedBy: CodingKeys.self).decode([Entry].self, forKey: .states)
        states = Dictionary(entries.map { ($0.id, $0.twap) }) { _, latest in latest }
    }
}
