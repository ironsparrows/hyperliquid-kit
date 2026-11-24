public import Foundation

extension Hyperliquid {
    /// An account's state: margin, balances, mode, fees, limits and history.
    ///
    /// Reached through ``API/account``. Every read takes the account's address in `user`; `nil` means
    /// the client's account, and without one the read throws ``ClientError/Reason/missingAccount``
    /// before anything is sent. Pass the account's own address, not an API wallet's: an API wallet's
    /// address reads as an empty account.
    public protocol AccountAPI: Sendable {
        // MARK: State

        /// The account's positions and margin on a perp DEX. (`clearinghouseState`)
        func perpetualState(dex: PerpDex, for user: Address?) async throws -> PerpetualState

        /// The account's token balances. In unified-account and portfolio-margin mode they hold all of
        /// its funds. (`spotClearinghouseState`)
        func balances(for user: Address?) async throws -> [Balance]

        /// How the account's spot and perp balances combine. (`userAbstraction`)
        func mode(for user: Address?) async throws -> AccountMode

        // MARK: Fees and limits

        /// The account's fee rates, discounts and daily volume. (`userFees`)
        func fees(for user: Address?) async throws -> Fees

        /// The account's action allowance. (`userRateLimit`)
        func rateLimit(for user: Address?) async throws -> RateLimit

        // MARK: Related addresses

        /// What the address is: an account, an API wallet, a vault or a sub-account. (`userRole`)
        func role(for user: Address?) async throws -> AccountRole

        /// The account's sub-accounts; empty when it has none, which Hyperliquid answers with `null`.
        /// (`subAccounts`)
        func subAccounts(for user: Address?) async throws -> [SubAccount]

        /// API wallets the account has approved, with their names and expiry. (`extraAgents`)
        func apiWallets(for user: Address?) async throws -> [APIWallet]

        // MARK: History

        /// The account's value and profit history over several windows. (`portfolio`)
        func portfolio(for user: Address?) async throws -> Portfolio

        /// Changes to the account's balances other than funding, from `start` to `end`, or to now when
        /// `end` is `nil`, oldest first. A response holds a limited number of updates (2000 were seen):
        /// to read further, ask again from the last one's time. (`userNonFundingLedgerUpdates`)
        func ledger(from start: Date, to end: Date?, for user: Address?) async throws -> [LedgerUpdate]
    }
}

// MARK: - Defaults

extension Hyperliquid.AccountAPI {
    /// The client's account's positions and margin on a perp DEX.
    public func perpetualState(dex: Hyperliquid.PerpDex) async throws -> Hyperliquid.PerpetualState {
        try await perpetualState(dex: dex, for: nil)
    }

    /// An account's positions and margin on the first perp DEX.
    public func perpetualState(for user: Hyperliquid.Address? = nil) async throws -> Hyperliquid.PerpetualState {
        try await perpetualState(dex: .first, for: user)
    }

    public func balances() async throws -> [Hyperliquid.Balance] {
        try await balances(for: nil)
    }

    public func mode() async throws -> Hyperliquid.AccountMode {
        try await mode(for: nil)
    }

    public func fees() async throws -> Hyperliquid.Fees {
        try await fees(for: nil)
    }

    public func rateLimit() async throws -> Hyperliquid.RateLimit {
        try await rateLimit(for: nil)
    }

    public func role() async throws -> Hyperliquid.AccountRole {
        try await role(for: nil)
    }

    public func subAccounts() async throws -> [Hyperliquid.SubAccount] {
        try await subAccounts(for: nil)
    }

    public func apiWallets() async throws -> [Hyperliquid.APIWallet] {
        try await apiWallets(for: nil)
    }

    public func portfolio() async throws -> Hyperliquid.Portfolio {
        try await portfolio(for: nil)
    }

    /// The client's account's ledger updates from `start` to `end`, oldest first.
    public func ledger(from start: Date, to end: Date) async throws -> [Hyperliquid.LedgerUpdate] {
        try await ledger(from: start, to: end, for: nil)
    }

    /// An account's ledger updates from `start` to now, oldest first.
    public func ledger(from start: Date, for user: Hyperliquid.Address? = nil) async throws
        -> [Hyperliquid.LedgerUpdate]
    {
        try await ledger(from: start, to: nil, for: user)
    }
}
