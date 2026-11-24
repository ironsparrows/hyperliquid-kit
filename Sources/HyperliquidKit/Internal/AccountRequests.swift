import Foundation
import HyperliquidKitCore

/// An account's state, read from `/info`.
struct AccountRequests: Hyperliquid.AccountAPI {
    let info: InfoClient
    /// The account a read uses when it is given none.
    let account: Hyperliquid.Address?

    // MARK: State

    func perpetualState(dex: Hyperliquid.PerpDex, for user: Hyperliquid.Address?) async throws
        -> Hyperliquid.PerpetualState
    {
        try await info.send(.clearinghouseState(try resolveAccount(user, default: account), dex: dex))
    }

    func balances(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.Balance] {
        try await info.send(.spotClearinghouseState(try resolveAccount(user, default: account))).balances
    }

    func mode(for user: Hyperliquid.Address?) async throws -> Hyperliquid.AccountMode {
        try await info.send(.userAbstraction(try resolveAccount(user, default: account)))
    }

    // MARK: Fees and limits

    func fees(for user: Hyperliquid.Address?) async throws -> Hyperliquid.Fees {
        try await info.send(.userFees(try resolveAccount(user, default: account)))
    }

    func rateLimit(for user: Hyperliquid.Address?) async throws -> Hyperliquid.RateLimit {
        try await info.send(.userRateLimit(try resolveAccount(user, default: account)))
    }

    // MARK: Related addresses

    func role(for user: Hyperliquid.Address?) async throws -> Hyperliquid.AccountRole {
        try await info.send(.userRole(try resolveAccount(user, default: account)))
    }

    func subAccounts(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.SubAccount] {
        try await info.send(.subAccounts(try resolveAccount(user, default: account))) ?? []
    }

    func apiWallets(for user: Hyperliquid.Address?) async throws -> [Hyperliquid.APIWallet] {
        try await info.send(.extraAgents(try resolveAccount(user, default: account)))
    }

    // MARK: History

    func portfolio(for user: Hyperliquid.Address?) async throws -> Hyperliquid.Portfolio {
        try await info.send(.portfolio(try resolveAccount(user, default: account)))
    }

    func ledger(from start: Date, to end: Date?, for user: Hyperliquid.Address?) async throws
        -> [Hyperliquid.LedgerUpdate]
    {
        try await info.send(.userNonFundingLedgerUpdates(try resolveAccount(user, default: account), from: start, to: end))
    }
}

// MARK: - Requests

extension InfoRequest where Response == Hyperliquid.PerpetualState {
    static func clearinghouseState(_ user: Hyperliquid.Address, dex: Hyperliquid.PerpDex) -> Self {
        Self("clearinghouseState", [userParameter(user), .init(key: "dex", value: .string(dex.name))])
    }
}

extension InfoRequest where Response == SpotState {
    static func spotClearinghouseState(_ user: Hyperliquid.Address) -> Self {
        Self("spotClearinghouseState", [userParameter(user)])
    }
}

extension InfoRequest where Response == Hyperliquid.AccountMode {
    static func userAbstraction(_ user: Hyperliquid.Address) -> Self {
        Self("userAbstraction", [userParameter(user)])
    }
}

extension InfoRequest where Response == Hyperliquid.Fees {
    static func userFees(_ user: Hyperliquid.Address) -> Self {
        Self("userFees", [userParameter(user)])
    }
}

extension InfoRequest where Response == Hyperliquid.RateLimit {
    static func userRateLimit(_ user: Hyperliquid.Address) -> Self {
        Self("userRateLimit", [userParameter(user)])
    }
}

extension InfoRequest where Response == Hyperliquid.AccountRole {
    static func userRole(_ user: Hyperliquid.Address) -> Self {
        Self("userRole", [userParameter(user)])
    }
}

extension InfoRequest where Response == [Hyperliquid.SubAccount]? {
    /// Hyperliquid answers `null` for an account without sub-accounts.
    static func subAccounts(_ user: Hyperliquid.Address) -> Self {
        Self("subAccounts", [userParameter(user)])
    }
}

extension InfoRequest where Response == [Hyperliquid.APIWallet] {
    static func extraAgents(_ user: Hyperliquid.Address) -> Self {
        Self("extraAgents", [userParameter(user)])
    }
}

extension InfoRequest where Response == Hyperliquid.Portfolio {
    static func portfolio(_ user: Hyperliquid.Address) -> Self {
        Self("portfolio", [userParameter(user)])
    }
}

extension InfoRequest where Response == [Hyperliquid.LedgerUpdate] {
    /// `endTime` is always sent, as `null` when there is none, which Hyperliquid reads as now.
    static func userNonFundingLedgerUpdates(_ user: Hyperliquid.Address, from start: Date, to end: Date?) -> Self {
        Self(
            "userNonFundingLedgerUpdates",
            [
                userParameter(user), .init(key: "startTime", value: .signed(start.wireMilliseconds)),
                .init(key: "endTime", value: end.map { .signed($0.wireMilliseconds) } ?? .null),
            ]
        )
    }
}
