import HyperliquidKitCore

/// Maps coins to the asset IDs and size decimals actions use, loading each perp DEX's `meta` once.
///
/// An asset ID is the perpetual's index in its perp DEX's `meta`. On the DEX at index `i` of
/// `perpDexs` (`i ≥ 1`), it is offset by `100000 + i × 10000`. A coin the loaded `meta` doesn't list
/// throws `unknownCoin`; nothing is reloaded. A spot or outcome coin throws `unsupportedMarket`
/// without loading anything. Only the names and size decimals are read, so a change
/// to any other field can't stop actions.
actor AssetDirectory {
    struct Asset: Hashable, Sendable {
        let id: Int
        let sizeDecimals: Int
    }

    private let info: InfoClient
    private var dexIndexes: Task<[Hyperliquid.PerpDex: Int], any Error>?
    private var assets: [Hyperliquid.PerpDex: Task<[Hyperliquid.Coin: Asset], any Error>] = [:]

    init(info: InfoClient) {
        self.info = info
    }

    func asset(for coin: Hyperliquid.Coin) async throws -> Asset {
        guard coin.kind == .perpetual else {
            throw Hyperliquid.ClientError(.unsupportedMarket, message: coin.name)
        }
        guard let asset = try await assets(on: coin.dex)[coin] else {
            throw Hyperliquid.ClientError(.unknownCoin, message: coin.name)
        }
        return asset
    }

    /// Throws `unknownCoin` unless Hyperliquid lists the perp DEX; the first perp DEX always passes.
    func check(_ dex: Hyperliquid.PerpDex) async throws {
        if dex != .first { _ = try await offset(of: dex) }
    }

    private func assets(on dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Coin: Asset] {
        let task = assets[dex] ?? Task { [info] in
            let offset = dex == .first ? 0 : try await self.offset(of: dex)
            let meta = InfoRequest<AssetMetadata>("meta", [.init(key: "dex", value: .string(dex.name))])
            return Dictionary(
                try await info.send(meta).universe.enumerated().map { index, entry in
                    (entry.name, Asset(id: offset + index, sizeDecimals: entry.szDecimals))
                }
            ) { first, _ in first }
        }
        assets[dex] = task
        do {
            return try await task.value
        } catch {
            // Forget a failed load so the next lookup tries again, unless another caller already did.
            if assets[dex] == task { assets[dex] = nil }
            throw error
        }
    }

    private func offset(of dex: Hyperliquid.PerpDex) async throws -> Int {
        let task = dexIndexes ?? Task { [info] in
            let names = try await info.send(InfoRequest<[PerpDexName?]>("perpDexs"))
            return Dictionary(
                names.enumerated().compactMap { index, entry in entry.map { (.named($0.name), index) } }
            ) { first, _ in first }
        }
        dexIndexes = task
        let indexes: [Hyperliquid.PerpDex: Int]
        do {
            indexes = try await task.value
        } catch {
            if dexIndexes == task { dexIndexes = nil }
            throw error
        }
        guard let index = indexes[dex] else {
            throw Hyperliquid.ClientError(.unknownCoin, message: "No perp DEX named \(dex.name)")
        }
        return 100_000 + index * 10_000
    }
}

// MARK: - Wire

/// The part of `meta` asset IDs need: each perpetual's name and size decimals.
private struct AssetMetadata: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let name: Hyperliquid.Coin
        let szDecimals: Int
    }

    let universe: [Entry]
}

/// The part of a `perpDexs` entry asset IDs need.
private struct PerpDexName: Decodable, Sendable {
    let name: String
}
