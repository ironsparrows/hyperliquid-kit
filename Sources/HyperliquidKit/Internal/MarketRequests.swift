import HyperliquidKitCore

/// Public market data, read from `/info`.
struct MarketRequests: Hyperliquid.MarketAPI {
    let info: InfoClient

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
