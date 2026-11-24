public import Foundation

extension Hyperliquid {
    /// An account's positions: what it can trade, the funding it has paid, and its leverage and margin.
    ///
    /// Reached through ``API/position``. Reads take the account's address in `user` as
    /// ``AccountAPI`` does: `nil` means the client's account, and without one the read throws
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
    public protocol PositionAPI: Sendable {
        /// What the account can trade in a perpetual at its current leverage. The coin is checked
        /// against its perp DEX's perpetuals first, as ``MarketAPI`` checks it. (`activeAssetData`)
        func tradingLimits(_ coin: Coin, for user: Address?) async throws -> TradingLimits

        /// The funding the account paid or received from `start` to `end`, or to now when `end` is
        /// `nil`, oldest first. Hyperliquid documents a response as holding at most 500
        /// payments: to read further, ask again from the last one's time. (`userFunding`)
        func fundingPayments(from start: Date, to end: Date?, for user: Address?) async throws -> [FundingPayment]

        // MARK: Actions

        /// Sets the leverage and margin mode for a perpetual, such as `.isolated(3)` or `.cross(10)`.
        /// (`updateLeverage`)
        ///
        /// A mode other than ``MarginMode/cross`` or ``MarginMode/isolated`` throws
        /// ``ClientError/Reason/invalidRequest`` before anything is sent.
        ///
        /// - Parameters:
        ///   - leverage: The leverage and its margin mode.
        ///   - coin: The perpetual.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        ///     An action rejected this way counts five times against the address's request limit.
        func setLeverage(_ leverage: Leverage, for coin: Coin, expiresAfter: Date?) async throws

        /// Adds margin to an isolated position, or removes it when `amount` is negative, in USD.
        /// (`updateIsolatedMargin`)
        ///
        /// An amount that is 0.001 millionths or more from a whole number of millionths of a dollar, or
        /// one too large to send, throws ``ClientError/Reason/invalidRequest`` before anything is sent.
        ///
        /// - Parameters:
        ///   - coin: The perpetual of the isolated position.
        ///   - amount: The USD to add, or to remove when negative.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func adjustMargin(_ coin: Coin, by amount: Decimal, expiresAfter: Date?) async throws

        /// Changes the position's isolated margin to target `leverage` instead of a USD amount.
        /// (`topUpIsolatedOnlyMargin`)
        ///
        /// A leverage that rounding to 8 decimals would change throws ``ClientError/Reason/invalidRequest`` before
        /// anything is sent.
        ///
        /// - Parameters:
        ///   - coin: The perpetual of the isolated position.
        ///   - leverage: The leverage the margin should give.
        ///   - expiresAfter: When set, Hyperliquid rejects the action if it arrives after this time.
        func topUpMargin(_ coin: Coin, toLeverage leverage: Decimal, expiresAfter: Date?) async throws
    }
}

// MARK: - Defaults

extension Hyperliquid.PositionAPI {
    // MARK: Actions

    public func setLeverage(_ leverage: Hyperliquid.Leverage, for coin: Hyperliquid.Coin) async throws {
        try await setLeverage(leverage, for: coin, expiresAfter: nil)
    }

    public func adjustMargin(_ coin: Hyperliquid.Coin, by amount: Decimal) async throws {
        try await adjustMargin(coin, by: amount, expiresAfter: nil)
    }

    public func topUpMargin(_ coin: Hyperliquid.Coin, toLeverage leverage: Decimal) async throws {
        try await topUpMargin(coin, toLeverage: leverage, expiresAfter: nil)
    }

    // MARK: Reads

    public func tradingLimits(_ coin: Hyperliquid.Coin) async throws -> Hyperliquid.TradingLimits {
        try await tradingLimits(coin, for: nil)
    }

    /// The client's account's funding payments from `start` to `end`, oldest first.
    public func fundingPayments(from start: Date, to end: Date) async throws -> [Hyperliquid.FundingPayment] {
        try await fundingPayments(from: start, to: end, for: nil)
    }

    /// An account's funding payments from `start` to now, oldest first.
    public func fundingPayments(from start: Date, for user: Hyperliquid.Address? = nil) async throws
        -> [Hyperliquid.FundingPayment]
    {
        try await fundingPayments(from: start, to: nil, for: user)
    }
}
