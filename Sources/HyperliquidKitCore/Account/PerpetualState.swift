public import Foundation

extension Hyperliquid {
    /// An account's positions and margin on one perp DEX.
    ///
    /// In unified-account and portfolio-margin mode, the account's balances are its spot balances and
    /// this state's margin summaries aren't meaningful; see ``AccountMode``.
    public struct PerpetualState: Hashable, Sendable {
        /// The open positions.
        public let positions: [Position]
        /// The account's margin on the perp DEX.
        public let marginSummary: MarginSummary
        /// The margin of the cross-margined positions.
        public let crossMarginSummary: MarginSummary
        /// The maintenance margin the cross-margined positions need, when Hyperliquid sends it.
        public let crossMaintenanceMarginUsed: Decimal?
        /// What the account can withdraw.
        public let withdrawable: Decimal
        /// When the state was read, when Hyperliquid sends it.
        public let time: Date?

        public init(
            positions: [Position], marginSummary: MarginSummary, crossMarginSummary: MarginSummary,
            crossMaintenanceMarginUsed: Decimal?, withdrawable: Decimal, time: Date?
        ) {
            self.positions = positions
            self.marginSummary = marginSummary
            self.crossMarginSummary = crossMarginSummary
            self.crossMaintenanceMarginUsed = crossMaintenanceMarginUsed
            self.withdrawable = withdrawable
            self.time = time
        }
    }
}

extension Hyperliquid.PerpetualState {
    /// The value and margin of a set of positions.
    public struct MarginSummary: Hashable, Sendable {
        public let accountValue: Decimal
        /// The positions' total notional value.
        public let totalNotionalPosition: Decimal
        /// Hyperliquid's `totalRawUsd`.
        public let totalRawUSD: Decimal
        public let totalMarginUsed: Decimal

        public init(accountValue: Decimal, totalNotionalPosition: Decimal, totalRawUSD: Decimal, totalMarginUsed: Decimal) {
            self.accountValue = accountValue
            self.totalNotionalPosition = totalNotionalPosition
            self.totalRawUSD = totalRawUSD
            self.totalMarginUsed = totalMarginUsed
        }
    }

    /// One open position.
    public struct Position: Hashable, Sendable {
        public let coin: Hyperliquid.Coin
        /// The size in the base coin: positive for a long, negative for a short.
        public let size: Decimal
        public let leverage: Hyperliquid.Leverage
        /// The average entry price, when Hyperliquid sends one.
        public let entryPrice: Decimal?
        /// The price at which the position is liquidated, or `nil` when there is none.
        public let liquidationPrice: Decimal?
        public let positionValue: Decimal
        public let unrealizedPnL: Decimal
        public let returnOnEquity: Decimal
        public let marginUsed: Decimal
        /// Hyperliquid's `rawUsd`, sent only for isolated margin. Its meaning isn't documented.
        public let rawUSD: Decimal?
        /// The market's maximum leverage, when Hyperliquid sends it.
        public let maxLeverage: Int?
        /// The funding the position has accumulated, when Hyperliquid sends it.
        public let cumulativeFunding: CumulativeFunding?

        public init(
            coin: Hyperliquid.Coin, size: Decimal, leverage: Hyperliquid.Leverage, entryPrice: Decimal?,
            liquidationPrice: Decimal?, positionValue: Decimal, unrealizedPnL: Decimal, returnOnEquity: Decimal,
            marginUsed: Decimal, rawUSD: Decimal? = nil, maxLeverage: Int? = nil,
            cumulativeFunding: CumulativeFunding? = nil
        ) {
            self.coin = coin
            self.size = size
            self.leverage = leverage
            self.entryPrice = entryPrice
            self.liquidationPrice = liquidationPrice
            self.positionValue = positionValue
            self.unrealizedPnL = unrealizedPnL
            self.returnOnEquity = returnOnEquity
            self.marginUsed = marginUsed
            self.rawUSD = rawUSD
            self.maxLeverage = maxLeverage
            self.cumulativeFunding = cumulativeFunding
        }
    }

    /// The funding a position has accumulated over three spans. Hyperliquid's `cumFunding`.
    public struct CumulativeFunding: Hashable, Sendable {
        public let allTime: Decimal
        public let sinceOpen: Decimal
        public let sinceChange: Decimal

        public init(allTime: Decimal, sinceOpen: Decimal, sinceChange: Decimal) {
            self.allTime = allTime
            self.sinceOpen = sinceOpen
            self.sinceChange = sinceChange
        }
    }
}

// MARK: - Wire

extension Hyperliquid.PerpetualState: Decodable {
    private enum CodingKeys: String, CodingKey {
        case assetPositions, marginSummary, crossMarginSummary, crossMaintenanceMarginUsed, withdrawable, time
    }

    /// Each `assetPositions` entry is `{position, type: "oneWay"}`.
    private struct AssetPosition: Decodable {
        let position: Position
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try container.decode([AssetPosition].self, forKey: .assetPositions).map(\.position)
        marginSummary = try container.decode(MarginSummary.self, forKey: .marginSummary)
        crossMarginSummary = try container.decode(MarginSummary.self, forKey: .crossMarginSummary)
        crossMaintenanceMarginUsed = try container.decodeIfPresent(WireDecimal.self, forKey: .crossMaintenanceMarginUsed)?
            .value
        withdrawable = try container.decode(WireDecimal.self, forKey: .withdrawable).value
        time = try container.decodeIfPresent(WireDate.self, forKey: .time)?.value
    }
}

extension Hyperliquid.PerpetualState.MarginSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case accountValue, totalNtlPos, totalRawUsd, totalMarginUsed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountValue = try container.decode(WireDecimal.self, forKey: .accountValue).value
        totalNotionalPosition = try container.decode(WireDecimal.self, forKey: .totalNtlPos).value
        totalRawUSD = try container.decode(WireDecimal.self, forKey: .totalRawUsd).value
        totalMarginUsed = try container.decode(WireDecimal.self, forKey: .totalMarginUsed).value
    }
}

extension Hyperliquid.PerpetualState.Position: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, szi, leverage, entryPx, liquidationPx, positionValue, unrealizedPnl, returnOnEquity, marginUsed
        case maxLeverage, cumFunding
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            try container.decode(WireDecimal.self, forKey: key).value
        }
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        size = try decimal(.szi)
        let leverage = try container.decode(WireLeverage.self, forKey: .leverage)
        self.leverage = leverage.leverage
        rawUSD = leverage.rawUSD
        entryPrice = try container.decodeIfPresent(WireDecimal.self, forKey: .entryPx)?.value
        liquidationPrice = try container.decodeIfPresent(WireDecimal.self, forKey: .liquidationPx)?.value
        positionValue = try decimal(.positionValue)
        unrealizedPnL = try decimal(.unrealizedPnl)
        returnOnEquity = try decimal(.returnOnEquity)
        marginUsed = try decimal(.marginUsed)
        maxLeverage = try container.decodeIfPresent(Int.self, forKey: .maxLeverage)
        cumulativeFunding = try container.decodeIfPresent(Hyperliquid.PerpetualState.CumulativeFunding.self, forKey: .cumFunding)
    }
}

extension Hyperliquid.PerpetualState.CumulativeFunding: Decodable {
    private enum CodingKeys: String, CodingKey {
        case allTime, sinceOpen, sinceChange
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allTime = try container.decode(WireDecimal.self, forKey: .allTime).value
        sinceOpen = try container.decode(WireDecimal.self, forKey: .sinceOpen).value
        sinceChange = try container.decode(WireDecimal.self, forKey: .sinceChange).value
    }
}
