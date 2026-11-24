public import Foundation

extension Hyperliquid {
    /// An account's TWAP orders.
    ///
    /// Reached through ``API/twap``. Reads take the account's address in `user` as ``AccountAPI``
    /// does: `nil` means the client's account, and without one the read throws
    /// ``ClientError/Reason/missingAccount``.
    ///
    /// Actions are signed by the client's signer, for its vault when it has one, and throw
    /// ``ClientError/Reason/missingSigner`` without one, and ``ClientError/Reason/unsupportedMarket`` for
    /// a spot or outcome coin, before anything is sent. An action that fails on the network, that
    /// Hyperliquid rejects, or whose answer the client can't read carries its nonce in the error.
    /// Cancelling the task throws `CancellationError`, which carries none: an action cancelled after it
    /// was sent may still execute.
    ///
    /// Until one of these actions commits, Hyperliquid deprioritizes all of the account's actions in
    /// its mempool, and those of its sub-accounts and the vaults it leads. Mempool priority applies
    /// only in standard account mode.
    public protocol TwapAPI: Sendable {
        /// The account's most recent TWAP slice fills, at most 2000. (`userTwapSliceFills`)
        func sliceFills(for user: Address?) async throws -> [TwapSliceFill]

        /// The account's TWAP orders and the statuses they reached. (`twapHistory`)
        func history(for user: Address?) async throws -> [TwapHistoryEntry]

        // MARK: Actions

        /// Places a TWAP order. (`twapOrder`)
        ///
        /// A rejected TWAP doesn't throw: its result carries Hyperliquid's reason. A duration that isn't
        /// a whole number of minutes, or a size with more than 8 decimals, throws
        /// ``ClientError/Reason/invalidRequest`` before anything is sent.
        ///
        /// - Parameter expiresAfter: When set, Hyperliquid rejects the action if it arrives after this
        ///   time. An action rejected this way counts five times against the address's request limit.
        func place(_ twap: TwapRequest, expiresAfter: Date?) async throws -> TwapPlacementResult

        /// Cancels a running TWAP order. (`twapCancel`)
        ///
        /// A TWAP that can't be canceled doesn't throw: its result carries Hyperliquid's reason.
        ///
        /// - Parameter expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func cancel(_ id: TwapID, coin: Coin, expiresAfter: Date?) async throws -> CancelResult
    }
}

// MARK: - Defaults

extension Hyperliquid.TwapAPI {
    public func place(_ twap: Hyperliquid.TwapRequest) async throws -> Hyperliquid.TwapPlacementResult {
        try await place(twap, expiresAfter: nil)
    }

    public func cancel(_ id: Hyperliquid.TwapID, coin: Hyperliquid.Coin) async throws -> Hyperliquid.CancelResult {
        try await cancel(id, coin: coin, expiresAfter: nil)
    }

    public func sliceFills() async throws -> [Hyperliquid.TwapSliceFill] {
        try await sliceFills(for: nil)
    }

    public func history() async throws -> [Hyperliquid.TwapHistoryEntry] {
        try await history(for: nil)
    }
}
