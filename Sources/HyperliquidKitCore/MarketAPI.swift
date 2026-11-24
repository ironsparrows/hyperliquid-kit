extension Hyperliquid {
    /// Public market data: perpetuals, their trading rules and their market state.
    ///
    /// Reached through ``API/market``. None of these requests needs an account or a signer.
    public protocol MarketAPI: Sendable {
        /// The perpetuals on a perp DEX, in asset-ID order, delisted ones included. (`meta`)
        func perpetuals(dex: PerpDex) async throws -> [Perpetual]

        /// The perpetuals on a perp DEX, each with its market state. (`metaAndAssetCtxs`)
        func perpetualContexts(dex: PerpDex) async throws -> [PerpetualContext]

        /// The perpetuals on every perp DEX, the first perp DEX's first. (`allPerpMetas`)
        func allPerpetuals() async throws -> [Perpetual]

        /// The builder-deployed perp DEXs, in Hyperliquid's order. (`perpDexs`)
        func perpDexs() async throws -> [PerpDex.Details]
    }
}

// MARK: - Defaults

extension Hyperliquid.MarketAPI {
    public func perpetuals() async throws -> [Hyperliquid.Perpetual] {
        try await perpetuals(dex: .first)
    }

    public func perpetualContexts() async throws -> [Hyperliquid.PerpetualContext] {
        try await perpetualContexts(dex: .first)
    }
}
