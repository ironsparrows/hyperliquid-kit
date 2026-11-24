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
    private var universes: [Hyperliquid.PerpDex: Task<Universe, any Error>] = [:]

    /// A perp DEX's perpetuals in `meta`'s order, and each one's position by name.
    private struct Universe: Sendable {
        let entries: [AssetMetadata.Entry]
        let positions: [Hyperliquid.Coin: Int]
    }

    init(info: InfoClient) {
        self.info = info
    }

    func asset(for coin: Hyperliquid.Coin) async throws -> Asset {
        guard coin.kind == .perpetual else {
            throw Hyperliquid.ClientError(.unsupportedMarket, message: coin.name)
        }
        let offset = coin.dex == .first ? 0 : try await offset(of: coin.dex)
        let universe = try await universe(of: coin.dex)
        guard let position = universe.positions[coin] else {
            throw Hyperliquid.ClientError(.unknownCoin, message: coin.name)
        }
        return Asset(id: offset + position, sizeDecimals: universe.entries[position].szDecimals)
    }

    /// Throws `unknownCoin` unless Hyperliquid lists the perp DEX; the first perp DEX always passes.
    func check(_ dex: Hyperliquid.PerpDex) async throws {
        if dex != .first { _ = try await offset(of: dex) }
    }

    /// The perp DEX's perpetuals in `meta`'s order, which positional pushes such as `pac` follow.
    /// Loaded by the perp DEX's name alone, so a perp DEX deployed after `perpDexs` was read still
    /// loads.
    func perpetuals(on dex: Hyperliquid.PerpDex) async throws -> [Hyperliquid.Coin] {
        try await universe(of: dex).entries.map(\.name)
    }

    private func universe(of dex: Hyperliquid.PerpDex) async throws -> Universe {
        let task = universes[dex] ?? Task { [info] in
            let entries = try await info.send(InfoRequest<AssetMetadata>("meta", [.init(key: "dex", value: .string(dex.name))]))
                .universe
            return Universe(
                entries: entries,
                positions: Dictionary(entries.enumerated().map { ($1.name, $0) }) { _, last in last }
            )
        }
        universes[dex] = task
        do {
            return try await task.valueUnlessCancelled
        } catch {
            // Forget a failed load so the next lookup tries again, unless another caller already did.
            // A waiter cancelled while the load runs leaves it for the others.
            if !(error is CancellationError), universes[dex] == task { universes[dex] = nil }
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
            indexes = try await task.valueUnlessCancelled
        } catch {
            if !(error is CancellationError), dexIndexes == task { dexIndexes = nil }
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
