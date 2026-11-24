import Foundation
import HyperliquidKitCore
import NIOConcurrencyHelpers

/// The compressed market feeds, each merging its pushes into a state. (`l2`, `fastAssetCtxs`, `pac`)
extension Streams {
    func orderBookUpdates(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision)
        -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error>
    {
        connection.stream(.l2(coin, precision: precision), initial: OrderBookState?.none) { state, data in
            switch try Self.payload(BookUpdatePush.self, of: data) {
            case .snapshot(let book):
                state = OrderBookState(snapshot: book)
            case .diff(let diff):
                // A diff that arrives before the snapshot has no book to apply to.
                guard state != nil else { return [] }
                try state?.apply(diff)
            case .unreadable:
                // Routing inflates every diff it can, so this one is lost, and the book with it.
                throw Self.uninflatable("l2")
            }
            return state.map { [$0.book] } ?? []
        }
    }

    func prices() -> AsyncThrowingStream<[Hyperliquid.Coin: Hyperliquid.MarketPrices], any Error> {
        connection.stream(.wholeMarket("fastAssetCtxs"), initial: [Hyperliquid.Coin: Hyperliquid.MarketPrices]()) {
            prices, data in
            let json = try Self.inflatedPayload("fastAssetCtxs", of: data)
            for (coin, update) in try JSONDecoder().decode([Hyperliquid.Coin: PricesUpdate].self, from: json) {
                prices[coin] = update.applied(to: prices[coin])
            }
            return [prices]
        }
    }

    func assetContexts() -> AsyncThrowingStream<[Hyperliquid.Coin: Hyperliquid.AssetContext], any Error> {
        let directory = connection.directory
        return connection.stream(.wholeMarket("pac"), initial: AssetContextsState()) { state, data in
            let json = try Self.inflatedPayload("pac", of: data)
            for dex in try JSONDecoder().decode([PerpDexContextsUpdate].self, from: json) {
                state.merge(dex.updates, on: dex.dex)
            }
            state.nameContexts(loadingNamesFrom: directory)
            // Nothing to show until a perp DEX's list has loaded.
            return state.contexts.isEmpty ? [] : [state.contexts]
        }
    }

    /// The inflated JSON of a compressed push `{"channel": …, "data": "<base64>"}`.
    private static func inflatedPayload(_ channel: String, of data: Data) throws -> Data {
        guard let json = inflated(base64: try payload(String.self, of: data)) else { throw uninflatable(channel) }
        return json
    }

    private static func uninflatable(_ channel: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: "A compressed \(channel) push doesn't inflate"))
    }
}

// MARK: - Subscriptions

extension StreamConnection.Subscription {
    /// `l2` for a coin, with `s` and `m` when the precision sets them; diffs are routed by coin.
    static func l2(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision) -> Self {
        Self(
            topic: .init(channel: "l2", key: coin.name),
            request: .map(
                [.init(key: "type", value: "l2"), .init(key: "c", value: .string(coin.name))]
                    + precision.wireParameters(significantFigures: "s", mantissa: "m")
            ),
            coin: coin, buildsOnSnapshot: true
        )
    }

    /// `{type}` for a feed of every market, whose first push is the complete state.
    static func wholeMarket(_ type: String) -> Self {
        Self(topic: .init(channel: type, key: ""), request: ["type": .string(type)], buildsOnSnapshot: true)
    }
}

// MARK: - Merging

/// The `pac` pushes merged so far, kept by perp DEX and position so that no update waits on a
/// perp DEX's list of names; the contexts are named once the list has loaded.
struct AssetContextsState: Sendable {
    private var fields: [Hyperliquid.PerpDex: [AssetContextFields]] = [:]
    /// Perp DEXs whose list has been asked for.
    private var requested: Set<Hyperliquid.PerpDex> = []
    /// The lists loaded so far, filled in by loads that run apart from the stream.
    private let names = NIOLockedValueBox<[Hyperliquid.PerpDex: [Hyperliquid.Coin]]>([:])
    private(set) var contexts: [Hyperliquid.Coin: Hyperliquid.AssetContext] = [:]

    /// Merges a perp DEX's updates, in its list's order, into its fields.
    mutating func merge(_ updates: [AssetContextUpdate], on dex: Hyperliquid.PerpDex) {
        var positions = fields[dex] ?? []
        if positions.count < updates.count {
            positions += Array(repeating: AssetContextFields(), count: updates.count - positions.count)
        }
        for (position, update) in updates.enumerated() where !update.isEmpty {
            positions[position].merge(update)
        }
        fields[dex] = positions
    }

    /// Starts loading, once per stream, the list of each perp DEX not asked for yet, without waiting
    /// for it, then names every position that has both a name and a complete context. A list that
    /// fails to load isn't asked for again, so that perp DEX stays out until the stream starts again;
    /// positions past the end of a list stay unnamed.
    mutating func nameContexts(loadingNamesFrom directory: AssetDirectory) {
        for dex in fields.keys where !requested.contains(dex) {
            requested.insert(dex)
            Task { [names] in
                guard let coins = try? await directory.perpetuals(on: dex) else { return }
                names.withLockedValue { $0[dex] = coins }
            }
        }
        let names = names.withLockedValue { $0 }
        var contexts: [Hyperliquid.Coin: Hyperliquid.AssetContext] = [:]
        for (dex, positions) in fields {
            guard let coins = names[dex] else { continue }
            for (coin, fields) in zip(coins, positions) {
                if let context = fields.context { contexts[coin] = context }
            }
        }
        self.contexts = contexts
    }
}

/// A perpetual's context fields as pushed so far: each one's latest value.
struct AssetContextFields: Sendable {
    private var values: [AssetContextUpdate.Key: Decimal] = [:]

    mutating func merge(_ update: AssetContextUpdate) {
        for (key, change) in update.changes { values[key] = change.applied(to: values[key]) }
    }

    /// The context, once every required field has a value. `pac` doesn't send a premium or impact
    /// prices, so those are `nil`.
    var context: Hyperliquid.AssetContext? {
        guard let markPrice = values[.markPx], let oraclePrice = values[.oraclePx],
            let previousDayPrice = values[.prevDayPx], let funding = values[.funding],
            let openInterest = values[.openInterest], let dayNotionalVolume = values[.dayNtlVlm]
        else { return nil }
        return .init(
            markPrice: markPrice, midPrice: values[.midPx], oraclePrice: oraclePrice, previousDayPrice: previousDayPrice,
            funding: funding, premium: nil, openInterest: openInterest, dayNotionalVolume: dayNotionalVolume,
            dayBaseVolume: values[.dayBaseVlm], impactBidPrice: nil, impactAskPrice: nil
        )
    }
}

/// How a push changes one field: a missing field is unchanged, `null` clears it, a value sets it.
enum FieldChange<Value: Sendable>: Sendable {
    case unchanged
    case cleared
    case set(Value)

    func applied(to value: Value?) -> Value? {
        switch self {
        case .unchanged: value
        case .cleared: nil
        case .set(let new): new
        }
    }
}

extension KeyedDecodingContainer {
    /// The change a push makes to a decimal field.
    func decodeChange(forKey key: Key) throws -> FieldChange<Decimal> {
        guard contains(key) else { return .unchanged }
        return try decodeNil(forKey: key) ? .cleared : .set(decode(WireDecimal.self, forKey: key).value)
    }
}

// MARK: - Wire

/// `l2` data: `{"s": book}` first, then `{"u": diff}`, a compressed diff arriving inflated in that
/// form; `{"c": …}` only when it didn't inflate.
private enum BookUpdatePush: Decodable {
    case snapshot(Hyperliquid.OrderBook)
    case diff(OrderBookDiff)
    case unreadable

    private enum CodingKeys: String, CodingKey {
        case s, u
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let book = try container.decodeIfPresent(Hyperliquid.OrderBook.self, forKey: .s) {
            self = .snapshot(book)
        } else if let diff = try container.decodeIfPresent(OrderBookDiff.self, forKey: .u) {
            self = .diff(diff)
        } else {
            self = .unreadable
        }
    }
}

/// A coin's `fastAssetCtxs` update: `{"markPx"?, "midPx"?}`. A `null` mid means the book has no mid.
private struct PricesUpdate: Decodable {
    let markPrice: FieldChange<Decimal>
    let midPrice: FieldChange<Decimal>

    private enum CodingKeys: String, CodingKey {
        case markPx, midPx
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markPrice = try container.decodeChange(forKey: .markPx)
        midPrice = try container.decodeChange(forKey: .midPx)
    }

    func applied(to prices: Hyperliquid.MarketPrices?) -> Hyperliquid.MarketPrices {
        .init(markPrice: markPrice.applied(to: prices?.markPrice), midPrice: midPrice.applied(to: prices?.midPrice))
    }
}

/// A `pac` entry: `[dex, [context update, …]]`, the updates in the order of the perp DEX's list.
private struct PerpDexContextsUpdate: Decodable {
    let dex: Hyperliquid.PerpDex
    let updates: [AssetContextUpdate]

    init(from decoder: any Decoder) throws {
        var pair = try decoder.unkeyedContainer()
        dex = try pair.decode(Hyperliquid.PerpDex.self)
        updates = try pair.decode([AssetContextUpdate].self)
    }
}

/// The fields of a context a `pac` push changes, `{}` when none changed: those the recorded pushes
/// carry.
struct AssetContextUpdate: Decodable, Sendable {
    enum Key: String, CodingKey, CaseIterable, Sendable {
        case markPx, midPx, oraclePx, prevDayPx, funding, openInterest, dayNtlVlm, dayBaseVlm
    }

    let changes: [Key: FieldChange<Decimal>]

    var isEmpty: Bool { changes.isEmpty }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var changes: [Key: FieldChange<Decimal>] = [:]
        for key in Key.allCases {
            let change = try container.decodeChange(forKey: key)
            if case .unchanged = change { continue }
            changes[key] = change
        }
        self.changes = changes
    }
}
