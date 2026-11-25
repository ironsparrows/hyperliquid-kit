import Foundation
import HyperliquidKitCore

/// Public market data, read from `/info`.
///
/// A request for one coin first checks the coin in `directory`, so a spot or outcome coin throws
/// `unsupportedMarket` and an unknown perpetual `unknownCoin` before the read is sent.
struct MarketEndpoints: Hyperliquid.MarketAPI {
    let info: InfoClient
    let directory: AssetDirectory

    // MARK: Perpetuals

    func perpetuals(dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Perpetual] {
        try await info.send(.meta(dex)).perpetuals
    }

    func perpetualContexts(dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.PerpetualContext] {
        let response = try await info.send(InfoRequest<MetaAndAssetContexts>("metaAndAssetCtxs", [dexParameter(dex)]))
        guard response.metadata.perpetuals.count == response.contexts.count else {
            throw HyperliquidError(
                .unexpectedResponse,
                message: "\(response.metadata.perpetuals.count) perpetuals but \(response.contexts.count) contexts"
            )
        }
        return zip(response.metadata.perpetuals, response.contexts).map(Hyperliquid.PerpetualContext.init)
    }

    func allPerpetuals() async throws -> [Hyperliquid.Perpetual] {
        try await info.send(InfoRequest<[PerpetualMetadata]>("allPerpMetas")).flatMap(\.perpetuals)
    }

    func perpDexs() async throws -> [Hyperliquid.PerpDex.Details] {
        try await info.send(.perpDexs).compactMap(\.self)
    }

    // MARK: Prices and trades

    func mids(dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Coin: Decimal] {
        try await info.send(.allMids(dex)).mapValues(\.value)
    }

    func orderBook(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision) async throws
        -> Hyperliquid.OrderBook
    {
        try await check(coin)
        return try await info.send(.l2Book(coin, precision: precision))
    }

    func candles(_ coin: Hyperliquid.Coin, interval: Hyperliquid.Candle.Interval, from start: Date, to end: Date)
        async throws -> [Hyperliquid.Candle]
    {
        try await check(coin)
        return try await info.send(.candleSnapshot(coin, interval: interval, from: start, to: end))
    }

    func recentTrades(_ coin: Hyperliquid.Coin) async throws -> [Hyperliquid.Trade] {
        try await check(coin)
        return try await info.send(.recentTrades(coin))
    }

    // MARK: Funding and limits

    func fundingHistory(_ coin: Hyperliquid.Coin, from start: Date, to end: Date?) async throws
        -> [Hyperliquid.FundingRate]
    {
        try await check(coin)
        return try await info.send(.fundingHistory(coin, from: start, to: end))
    }

    func openInterestCapped(dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Coin] {
        try await info.send(.perpsAtOpenInterestCap(dex))
    }

    func predictedFundings() async throws -> [Hyperliquid.PredictedFunding] {
        try await info.send(.predictedFundings)
    }

    func perpDexLimits(dex: Hyperliquid.PerpDex) async throws -> Hyperliquid.PerpDex.Limits? {
        // Hyperliquid refuses the first perp DEX's empty name here.
        guard dex != .first else { return nil }
        return try await info.send(.perpDexLimits(dex))
    }

    func perpDexStatus(dex: Hyperliquid.PerpDex) async throws -> Hyperliquid.PerpDex.Status {
        try await info.send(.perpDexStatus(dex))
    }

    // MARK: Exchange

    func exchangeStatus() async throws -> Hyperliquid.ExchangeStatus {
        try await info.send(.exchangeStatus)
    }

    // MARK: Checking coins

    /// Throws `unsupportedMarket` for a spot or outcome coin, `unknownCoin` unless the coin's perp DEX
    /// lists it.
    private func check(_ coin: Hyperliquid.Coin) async throws {
        _ = try await directory.asset(for: coin)
    }
}

// MARK: - Requests

extension InfoRequest where Response == [Hyperliquid.Coin: WireDecimal] {
    static func allMids(_ dex: Hyperliquid.PerpDex) -> Self {
        Self("allMids", [dexParameter(dex)])
    }
}

extension InfoRequest where Response == Hyperliquid.OrderBook {
    /// `nSigFigs` and `mantissa` are sent only when the precision sets them.
    static func l2Book(_ coin: Hyperliquid.Coin, precision: Hyperliquid.OrderBook.Precision) -> Self {
        Self("l2Book", [coinParameter(coin)] + precision.wireParameters)
    }
}

extension InfoRequest where Response == [Hyperliquid.Candle] {
    /// The parameters go inside `req`, times in milliseconds.
    static func candleSnapshot(
        _ coin: Hyperliquid.Coin, interval: Hyperliquid.Candle.Interval, from start: Date, to end: Date
    ) -> Self {
        let request: ActionValue = [
            "coin": .string(coin.name),
            "interval": .string(interval.rawValue),
            "startTime": .signed(start.wireMilliseconds),
            "endTime": .signed(end.wireMilliseconds),
        ]
        return Self("candleSnapshot", [.init(key: "req", value: request)])
    }
}

extension InfoRequest where Response == [Hyperliquid.Trade] {
    static func recentTrades(_ coin: Hyperliquid.Coin) -> Self {
        Self("recentTrades", [coinParameter(coin)])
    }
}

extension InfoRequest where Response == [Hyperliquid.FundingRate] {
    /// `endTime` is left out when there is none, which Hyperliquid reads as now.
    static func fundingHistory(_ coin: Hyperliquid.Coin, from start: Date, to end: Date?) -> Self {
        var parameters = [coinParameter(coin), .init(key: "startTime", value: .signed(start.wireMilliseconds))]
        if let end {
            parameters.append(.init(key: "endTime", value: .signed(end.wireMilliseconds)))
        }
        return Self("fundingHistory", parameters)
    }
}

extension InfoRequest where Response == [Hyperliquid.Coin] {
    static func perpsAtOpenInterestCap(_ dex: Hyperliquid.PerpDex) -> Self {
        Self("perpsAtOpenInterestCap", [dexParameter(dex)])
    }
}

extension InfoRequest where Response == [Hyperliquid.PredictedFunding] {
    static let predictedFundings = Self("predictedFundings")
}

extension InfoRequest where Response == Hyperliquid.PerpDex.Limits? {
    /// Hyperliquid answers `null` for the first perp DEX.
    static func perpDexLimits(_ dex: Hyperliquid.PerpDex) -> Self {
        Self("perpDexLimits", [dexParameter(dex)])
    }
}

extension InfoRequest where Response == Hyperliquid.PerpDex.Status {
    static func perpDexStatus(_ dex: Hyperliquid.PerpDex) -> Self {
        Self("perpDexStatus", [dexParameter(dex)])
    }
}

extension InfoRequest where Response == Hyperliquid.ExchangeStatus {
    static let exchangeStatus = Self("exchangeStatus")
}

extension InfoRequest where Response == PerpetualMetadata {
    static func meta(_ dex: Hyperliquid.PerpDex) -> Self {
        Self("meta", [dexParameter(dex)])
    }
}

extension InfoRequest where Response == [Hyperliquid.PerpDex.Details?] {
    /// The first entry is `null`: the first perp DEX isn't builder-deployed.
    static let perpDexs = Self("perpDexs")
}

/// `dex`, which Hyperliquid reads as the first perp DEX when it is empty.
private func dexParameter(_ dex: Hyperliquid.PerpDex) -> ActionValue.Entry {
    .init(key: "dex", value: .string(dex.name))
}

private func coinParameter(_ coin: Hyperliquid.Coin) -> ActionValue.Entry {
    .init(key: "coin", value: .string(coin.name))
}

// MARK: - Wire

/// `[meta, [context]]`: the contexts follow the perpetuals' order.
private struct MetaAndAssetContexts: Decodable, Sendable {
    let metadata: PerpetualMetadata
    let contexts: [Hyperliquid.AssetContext]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        metadata = try container.decode(PerpetualMetadata.self)
        contexts = try container.decode([Hyperliquid.AssetContext].self)
    }
}
