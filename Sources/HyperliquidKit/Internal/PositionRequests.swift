import Foundation
import HyperliquidKitCore

/// An account's position reads, from `/info`.
struct PositionRequests: Hyperliquid.PositionAPI {
    let info: InfoClient
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
