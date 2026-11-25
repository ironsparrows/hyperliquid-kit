import Foundation
import HyperliquidKitCore

/// An account's position reads, from `/info`, and its leverage and margin actions, sent to `/exchange`.
struct PositionEndpoints: Hyperliquid.PositionAPI {
    let info: InfoClient
    let exchange: ExchangeClient
    let directory: AssetDirectory
    /// The account a read uses when it is given none.
    let account: Hyperliquid.Address?

    func tradingLimits(_ coin: Hyperliquid.Coin, for user: Hyperliquid.Address?) async throws
        -> Hyperliquid.TradingLimits
    {
        let user = try resolveAccount(user, default: account)
        _ = try await directory.asset(for: coin)
        return try await info.send(.activeAssetData(user, coin: coin))
    }

    func fundingPayments(from start: Date, to end: Date?, for user: Hyperliquid.Address?) async throws
        -> [Hyperliquid.FundingPayment]
    {
        try await info.send(.userFunding(try resolveAccount(user, default: account), from: start, to: end))
    }
}

// MARK: - Actions

extension PositionEndpoints {
    func setLeverage(_ leverage: Hyperliquid.Leverage, for coin: Hyperliquid.Coin, expiresAfter: Date?) async throws {
        _ = try exchange.requireSigner()
        guard leverage.mode == .cross || leverage.mode == .isolated else {
            throw Hyperliquid.ClientError(
                .invalidRequest, message: "Leverage can be set only with cross or isolated margin, not \(leverage.mode.rawValue)"
            )
        }
        let asset = try await directory.asset(for: coin).id
        let action: ActionValue = [
            "type": "updateLeverage", "asset": .unsigned(UInt64(asset)), "isCross": .bool(leverage.mode == .cross),
            "leverage": .signed(Int64(leverage.value)),
        ]
        try await exchange.perform(action, expiresAfter: expiresAfter)
    }

    func adjustMargin(_ coin: Hyperliquid.Coin, by amount: Decimal, expiresAfter: Date?) async throws {
        _ = try exchange.requireSigner()
        let ntli = try microdollars(amount, "margin amount")
        let asset = try await directory.asset(for: coin).id
        // `isBuy` is always true: Hyperliquid ignores it until it offers hedge mode.
        let action: ActionValue = [
            "type": "updateIsolatedMargin", "asset": .unsigned(UInt64(asset)), "isBuy": true, "ntli": .signed(ntli),
        ]
        try await exchange.perform(action, expiresAfter: expiresAfter)
    }

    func topUpMargin(_ coin: Hyperliquid.Coin, toLeverage leverage: Decimal, expiresAfter: Date?) async throws {
        _ = try exchange.requireSigner()
        let text = try wireNumber(leverage, "leverage")
        let asset = try await directory.asset(for: coin).id
        let action: ActionValue = [
            "type": "topUpIsolatedOnlyMargin", "asset": .unsigned(UInt64(asset)), "leverage": .string(text),
        ]
        try await exchange.perform(action, expiresAfter: expiresAfter)
    }
}

// MARK: - Requests

extension InfoRequest where Response == Hyperliquid.TradingLimits {
    static func activeAssetData(_ user: Hyperliquid.Address, coin: Hyperliquid.Coin) -> Self {
        Self("activeAssetData", [userParameter(user), .init(key: "coin", value: .string(coin.name))])
    }
}

extension InfoRequest where Response == [Hyperliquid.FundingPayment] {
    /// `endTime` is left out when there is none, which Hyperliquid reads as now.
    static func userFunding(_ user: Hyperliquid.Address, from start: Date, to end: Date?) -> Self {
        var parameters = [userParameter(user), .init(key: "startTime", value: .signed(start.wireMilliseconds))]
        if let end {
            parameters.append(.init(key: "endTime", value: .signed(end.wireMilliseconds)))
        }
        return Self("userFunding", parameters)
    }
}
