extension Hyperliquid {
    /// An account's TWAP orders.
    ///
    /// Reached through ``API/twap``. Reads take the account's address in `user` as ``AccountAPI``
    /// does: `nil` means the client's account, and without one the read throws
    /// ``ClientError/Reason/missingAccount``.
    public protocol TwapAPI: Sendable {
        /// The account's most recent TWAP slice fills, at most 2000. (`userTwapSliceFills`)
        func sliceFills(for user: Address?) async throws -> [TwapSliceFill]

        /// The account's TWAP orders and the statuses they reached. (`twapHistory`)
        func history(for user: Address?) async throws -> [TwapHistoryEntry]
    }
}

// MARK: - Defaults

extension Hyperliquid.TwapAPI {
    public func sliceFills() async throws -> [Hyperliquid.TwapSliceFill] {
        try await sliceFills(for: nil)
    }

    public func history() async throws -> [Hyperliquid.TwapHistoryEntry] {
        try await history(for: nil)
    }
}
