import HyperliquidKitCore
import NIOConcurrencyHelpers

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
        let task =
            universes[dex]
            ?? Task { [info] in
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
            // Forget a failed load so the next lookup tries again, unless another caller already did. A
            // lookup canceled while the load runs leaves it for the others; if that load then fails,
            // the next lookup gets its error and forgets it.
            if !(error is CancellationError && Task.isCancelled), universes[dex] == task { universes[dex] = nil }
            throw error
        }
    }

    private func offset(of dex: Hyperliquid.PerpDex) async throws -> Int {
        let task =
            dexIndexes
            ?? Task { [info] in
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
            if !(error is CancellationError && Task.isCancelled), dexIndexes == task { dexIndexes = nil }
            throw error
        }
        guard let index = indexes[dex] else {
            throw Hyperliquid.ClientError(.unknownCoin, message: "No perp DEX named \(dex.name)")
        }
        return 100_000 + index * 10_000
    }
}

// MARK: - Waiting for a shared load

extension Task where Failure == any Error {
    /// The task's value, or `CancellationError` as soon as the waiting task is canceled. The task
    /// itself keeps running for its other waiters; a canceled waiter leaves a small task behind until
    /// it ends.
    fileprivate var valueUnlessCancelled: Success {
        get async throws {
            let waiter = Waiter<Success>()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiter.wait(continuation)
                    Task<Void, Never> { waiter.finish(with: await result) }
                }
            } onCancel: {
                waiter.finish(with: .failure(Swift.CancellationError()))
            }
        }
    }
}

/// Hands one waiting continuation the first of a task's result and the waiter's cancellation.
private final class Waiter<Success: Sendable>: Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Success, any Error>)
        /// Finished before the continuation arrived: it resumes with this as soon as it does.
        case finished(Result<Success, any Error>)
        case resumed
    }

    private let state = NIOLockedValueBox(State.idle)

    func wait(_ continuation: CheckedContinuation<Success, any Error>) {
        let early: Result<Success, any Error>? = state.withLockedValue { state in
            if case .finished(let result) = state {
                state = .resumed
                return result
            }
            state = .waiting(continuation)
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func finish(with result: Result<Success, any Error>) {
        let waiting: CheckedContinuation<Success, any Error>? = state.withLockedValue { state in
            switch state {
            case .idle:
                state = .finished(result)
                return nil
            case .waiting(let continuation):
                state = .resumed
                return continuation
            case .finished, .resumed:
                return nil
            }
        }
        waiting?.resume(with: result)
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
