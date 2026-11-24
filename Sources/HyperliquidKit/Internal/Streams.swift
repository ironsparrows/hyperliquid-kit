import Foundation
import HyperliquidKitCore

/// Live pushes over the client's ``StreamConnection``.
struct Streams: Hyperliquid.StreamAPI {
    let connection: StreamConnection

    func mids(dex: Hyperliquid.PerpDex) -> AsyncThrowingStream<[Hyperliquid.Coin: Decimal], any Error> {
        connection.stream(.allMids(dex), buffering: .latest) { data in
            try Self.payload(MidsPush.self, of: data).mids.mapValues(\.value)
        }
    }

    func orderBook(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision)
        -> AsyncThrowingStream<Hyperliquid.OrderBook, any Error>
    {
        connection.stream(.l2Book(coin, precision: precision), buffering: .latest) { data in
            try Self.payload(Hyperliquid.OrderBook.self, of: data)
        }
    }

    func bestBidOffer(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.BestBidOffer, any Error> {
        connection.stream(.coin("bbo", coin), buffering: .latest) { data in
            try Self.payload(Hyperliquid.BestBidOffer.self, of: data)
        }
    }

    func trades(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<[Hyperliquid.Trade], any Error> {
        connection.stream(.coin("trades", coin), buffering: .all) { data in
            try Self.payload([Hyperliquid.Trade].self, of: data)
        }
    }

    func candles(_ coin: Hyperliquid.Coin, interval: Hyperliquid.Candle.Interval)
        -> AsyncThrowingStream<Hyperliquid.Candle, any Error>
    {
        connection.stream(.candle(coin, interval: interval), buffering: .all, decodeEach: { data in
            try Self.payload(CandlePush.self, of: data).candles
        })
    }

    func assetContext(_ coin: Hyperliquid.Coin) -> AsyncThrowingStream<Hyperliquid.AssetContext, any Error> {
        connection.stream(.coin("activeAssetCtx", coin), buffering: .latest) { data in
            try Self.payload(AssetContextPush.self, of: data).ctx
        }
    }

    func disconnect() async {
        await connection.disconnect()
    }

    /// The `data` of a push `{"channel": …, "data": …}`.
    private static func payload<Payload: Decodable>(_ type: Payload.Type, of data: Data) throws -> Payload {
        try JSONDecoder().decode(Push<Payload>.self, from: data).data
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
            request: .map([.init(key: "type", value: "l2Book"), .init(key: "coin", value: .string(coin.name))]
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
}

// MARK: - Wire

/// `{"channel": …, "data": …}`.
private struct Push<Payload: Decodable>: Decodable {
    let data: Payload
}

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
