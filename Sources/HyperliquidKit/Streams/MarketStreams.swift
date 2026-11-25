import Foundation
import HyperliquidKitCore
import NIOConcurrencyHelpers

/// The market streams over the client's ``StreamConnection``, and the compressed market feeds (`l2`,
/// `fastAssetCtxs`, `pac`), each merging its pushes into a state.
struct MarketStreams: Sendable {
    let connection: StreamConnection

    // MARK: Markets

    func mids(dex: Hyperliquid.PerpDex) -> AsyncThrowingStream<[Hyperliquid.Coin: Decimal], any Error> {
        connection.stream(.allMids(dex), buffering: .latest) { data in
            try StreamConnection.payload(MidsPush.self, of: data).mids.mapValues(\.value)
        }
    }

    func orderBook(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision)
        -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error>
    {
        connection.stream(.l2Book(coin, precision: precision), buffering: .latest) { data in
            try StreamConnection.payload(Hyperliquid.OrderBook.self, of: data)
        }
    }

    func bestBidOffer(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.BestBidOffer, any Error> {
        connection.stream(.coin("bbo", coin), buffering: .latest) { data in
            try StreamConnection.payload(Hyperliquid.BestBidOffer.self, of: data)
        }
    }

    func trades(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<[Hyperliquid.Trade], any Error> {
        connection.stream(.coin("trades", coin), buffering: .all) { data in
            try StreamConnection.payload([Hyperliquid.Trade].self, of: data)
        }
    }

    func candles(_ coin: Hyperliquid.Coin, interval: Hyperliquid.Candle.Interval)
        -> AsyncThrowingStream<Hyperliquid.Candle, any Error>
    {
        connection.stream(
            .candle(coin, interval: interval), buffering: .all,
            decodeEach: { data in
                try StreamConnection.payload(CandlePush.self, of: data).candles
            })
    }

    func assetContext(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.AssetContext, any Error> {
        connection.stream(.coin("activeAssetCtx", coin), buffering: .latest) { data in
            try StreamConnection.payload(AssetContextPush.self, of: data).ctx
        }
    }

    // MARK: Compressed feeds

    func orderBookUpdates(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision)
        -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error>
    {
        connection.stream(.l2(coin, precision: precision), initial: OrderBookState?.none) { state, data in
            switch try StreamConnection.payload(BookUpdatePush.self, of: data) {
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

    // MARK: Inflating

    /// The inflated JSON of a compressed push `{"channel": …, "data": "<base64>"}`.
    private static func inflatedPayload(_ channel: String, of data: Data) throws -> Data {
        guard let json = inflated(base64: try StreamConnection.payload(String.self, of: data)) else {
            throw uninflatable(channel)
        }
        return json
    }

    private static func uninflatable(_ channel: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: "A compressed \(channel) push doesn't inflate"))
    }
}

// MARK: - Subscriptions

extension StreamConnection.Subscription {
    /// `allMids`, with `dex` for a builder-deployed perp DEX, which is checked first; a push from the
    /// first perp DEX carries no `dex`.
    static func allMids(_ dex: Hyperliquid.PerpDex) -> Self {
        Self(
            topic: .init(channel: "allMids", key: dex.name),
            request: dex == .first ? ["type": "allMids"] : ["type": "allMids", "dex": .string(dex.name)],
            dex: dex
        )
    }

    /// `l2Book` for a coin, with `nSigFigs` and `mantissa` when the precision sets them.
    static func l2Book(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision) -> Self {
        Self(
            topic: .init(channel: "l2Book", key: coin.name),
            request: .map(
                [.init(key: "type", value: "l2Book"), .init(key: "coin", value: .string(coin.name))]
                    + precision.wireParameters),
            coin: coin
        )
    }

    /// `{type, coin}` for a channel that takes only a coin: `bbo`, `trades`, `activeAssetCtx`.
    static func coin(_ type: String, _ coin: Hyperliquid.Coin) -> Self {
        Self(
            topic: .init(channel: type, key: coin.name), request: ["type": .string(type), "coin": .string(coin.name)],
            coin: coin
        )
    }

    /// `candle` for a coin and interval; pushes are routed by both.
    static func candle(_ coin: Hyperliquid.Coin, interval: Hyperliquid.Candle.Interval) -> Self {
        Self(
            topic: .init(channel: "candle", key: "\(coin.name),\(interval.rawValue)"),
            request: ["type": "candle", "coin": .string(coin.name), "interval": .string(interval.rawValue)],
            coin: coin
        )
    }

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

/// A book kept up to date from `l2` diffs, starting from the snapshot Hyperliquid sends first.
struct OrderBookState: Sendable {
    private(set) var book: Hyperliquid.OrderBook

    init(snapshot: Hyperliquid.OrderBook) {
        book = snapshot
    }

    /// Applies a diff to each side: removes the levels at its indexes into the book as it was, then adds
    /// or replaces its levels by price, then sorts the side best price first.
    ///
    /// - Throws: ``HyperliquidError`` with kind `unexpectedResponse` when the diff removes
    ///   a level the book doesn't have, which means the book no longer matches Hyperliquid's.
    mutating func apply(_ diff: OrderBookDiff) throws {
        book = Hyperliquid.OrderBook(
            coin: book.coin, time: diff.time,
            bids: try Self.side(book.bids, removing: diff.removedBids, adding: diff.bids) { $0 > $1 },
            asks: try Self.side(book.asks, removing: diff.removedAsks, adding: diff.asks) { $0 < $1 }
        )
    }

    private static func side(
        _ levels: [Hyperliquid.OrderBook.Level], removing removed: [Int], adding added: [Hyperliquid.OrderBook.Level],
        bestFirst: (Decimal, Decimal) -> Bool
    ) throws -> [Hyperliquid.OrderBook.Level] {
        var levels = levels
        // From the last index down, so each index still points into the book as it was.
        for index in Set(removed).sorted(by: >) {
            guard levels.indices.contains(index) else {
                throw HyperliquidError(
                    .unexpectedResponse,
                    message: "A book diff removes level \(index) of a side with \(levels.count): the book is out of step"
                )
            }
            levels.remove(at: index)
        }
        for level in added {
            if let index = levels.firstIndex(where: { $0.price == level.price }) {
                levels[index] = level
            } else {
                levels.append(level)
            }
        }
        return levels.sorted { bestFirst($0.price, $1.price) }
    }
}

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

/// `allMids` data: `{"mids": {coin: "price"}, "dex"?}`.
private struct MidsPush: Decodable {
    let mids: [Hyperliquid.Coin: WireDecimal]
}

/// `candle` data: one candle, as Hyperliquid sends it, or a list, as its subscriptions page types it.
private struct CandlePush: Decodable {
    let candles: [Hyperliquid.Candle]

    init(from decoder: any Decoder) throws {
        if (try? decoder.unkeyedContainer()) != nil {
            candles = try decoder.singleValueContainer().decode([Hyperliquid.Candle].self)
        } else {
            candles = [try Hyperliquid.Candle(from: decoder)]
        }
    }
}

/// `activeAssetCtx` data: `{"coin": …, "ctx": …}`.
private struct AssetContextPush: Decodable {
    let ctx: Hyperliquid.AssetContext
}

/// An `l2` diff: `{"c": coin, "t": time, "l": [bids, asks] added or changed, "r": [bids, asks] removed
/// indexes}`, levels `{"p": price, "s": size}` without an order count.
struct OrderBookDiff: Decodable, Sendable {
    let time: Date
    let bids: [Hyperliquid.OrderBook.Level]
    let asks: [Hyperliquid.OrderBook.Level]
    let removedBids: [Int]
    let removedAsks: [Int]

    private enum CodingKeys: String, CodingKey {
        case t, l, r
    }

    private struct Level: Decodable {
        let p: WireDecimal
        let s: WireDecimal

        var level: Hyperliquid.OrderBook.Level {
            .init(price: p.value, size: s.value, orderCount: nil)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(WireDate.self, forKey: .t).value
        var levels = try container.nestedUnkeyedContainer(forKey: .l)
        bids = try levels.decode([Level].self).map(\.level)
        asks = try levels.decode([Level].self).map(\.level)
        var removed = try container.nestedUnkeyedContainer(forKey: .r)
        removedBids = try removed.decode([Int].self)
        removedAsks = try removed.decode([Int].self)
    }
}

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
