// Each vocabulary is a struct with static members, not an enum, so a value Hyperliquid adds later
// still decodes, keeps its raw value and encodes back unchanged.

// MARK: - Orders

extension Hyperliquid {
    /// Which side of the book an order or trade is on.
    public struct Side: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// Hyperliquid's `"B"` (bid).
        public static let buy = Self(rawValue: "B")
        /// Hyperliquid's `"A"` (ask).
        public static let sell = Self(rawValue: "A")
    }

    /// How long a limit order stays on the book.
    public struct TimeInForce: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// Rests on the book until it fills or is canceled.
        public static let goodTilCanceled = Self(rawValue: "Gtc")
        /// Post-only: canceled instead of matching immediately.
        public static let addLiquidityOnly = Self(rawValue: "Alo")
        /// Fills what it can immediately and cancels the rest.
        public static let immediateOrCancel = Self(rawValue: "Ioc")
        /// A market order placed from Hyperliquid's own app. Seen on orders, not offered when placing one.
        public static let frontendMarket = Self(rawValue: "FrontendMarket")
        /// An order the liquidation engine placed. Seen on orders, not offered when placing one.
        public static let liquidationMarket = Self(rawValue: "LiquidationMarket")
    }

    /// Whether a trigger order takes profit or stops a loss.
    public struct TriggerKind: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let takeProfit = Self(rawValue: "tp")
        public static let stopLoss = Self(rawValue: "sl")
    }

    /// Where an order is in its life: on the book, filled, or the reason it was canceled or rejected.
    public struct OrderStatus: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        // MARK: Live and done

        /// Placed and not yet final.
        public static let open = Self(rawValue: "open")
        public static let filled = Self(rawValue: "filled")
        /// Canceled by the account.
        public static let canceled = Self(rawValue: "canceled")
        /// A trigger order whose trigger price traded.
        public static let triggered = Self(rawValue: "triggered")
        /// Rejected when it was placed.
        public static let rejected = Self(rawValue: "rejected")

        // MARK: Canceled by Hyperliquid

        /// Canceled because the account lacked the margin to fill it.
        public static let marginCanceled = Self(rawValue: "marginCanceled")
        /// Canceled because a user withdrew from the vault that placed it.
        public static let vaultWithdrawalCanceled = Self(rawValue: "vaultWithdrawalCanceled")
        /// Canceled for being too aggressive while open interest was at its cap.
        public static let openInterestCapCanceled = Self(rawValue: "openInterestCapCanceled")
        /// Canceled by self-trade prevention.
        public static let selfTradeCanceled = Self(rawValue: "selfTradeCanceled")
        /// A reduce-only order canceled because it would no longer reduce the position.
        public static let reduceOnlyCanceled = Self(rawValue: "reduceOnlyCanceled")
        /// A take-profit or stop-loss canceled because its sibling filled.
        public static let siblingFilledCanceled = Self(rawValue: "siblingFilledCanceled")
        /// Canceled because the market was delisted.
        public static let delistedCanceled = Self(rawValue: "delistedCanceled")
        /// Canceled because the account was liquidated.
        public static let liquidatedCanceled = Self(rawValue: "liquidatedCanceled")
        /// Canceled when a scheduled cancel (dead man's switch) passed its deadline.
        public static let scheduledCancel = Self(rawValue: "scheduledCancel")

        // MARK: Rejected

        /// The price isn't a multiple of the tick size.
        public static let tickRejected = Self(rawValue: "tickRejected")
        /// The order's value is below the minimum.
        public static let minTradeNotionalRejected = Self(rawValue: "minTradeNtlRejected")
        /// The account lacks the margin for the order.
        public static let perpMarginRejected = Self(rawValue: "perpMarginRejected")
        /// A reduce-only order would increase the position.
        public static let reduceOnlyRejected = Self(rawValue: "reduceOnlyRejected")
        /// A post-only (``TimeInForce/addLiquidityOnly``) order would have matched immediately.
        public static let badAddLiquidityOnlyPriceRejected = Self(rawValue: "badAloPxRejected")
        /// An immediate-or-cancel order found nothing to match.
        public static let immediateOrCancelRejected = Self(rawValue: "iocCancelRejected")
        /// The take-profit or stop-loss trigger price is invalid.
        public static let badTriggerPriceRejected = Self(rawValue: "badTriggerPxRejected")
        /// A market order found no liquidity.
        public static let marketOrderNoLiquidityRejected = Self(rawValue: "marketOrderNoLiquidityRejected")
        /// The order would increase a position while open interest is at its cap.
        public static let positionIncreaseAtOpenInterestCapRejected = Self(
            rawValue: "positionIncreaseAtOpenInterestCapRejected"
        )
        /// The order would flip a position while open interest is at its cap.
        public static let positionFlipAtOpenInterestCapRejected = Self(
            rawValue: "positionFlipAtOpenInterestCapRejected"
        )
        /// The price was more aggressive than the oracle while open interest is at its cap.
        public static let tooAggressiveAtOpenInterestCapRejected = Self(
            rawValue: "tooAggressiveAtOpenInterestCapRejected"
        )
        /// The order would increase open interest too quickly.
        public static let openInterestIncreaseRejected = Self(rawValue: "openInterestIncreaseRejected")
        /// A spot order lacked the balance to trade.
        public static let insufficientSpotBalanceRejected = Self(rawValue: "insufficientSpotBalanceRejected")
        /// The price is too far from the oracle price.
        public static let oracleRejected = Self(rawValue: "oracleRejected")
        /// The position would exceed the margin tier's limit at the current leverage.
        public static let perpMaxPositionRejected = Self(rawValue: "perpMaxPositionRejected")
    }
}

// MARK: - Accounts

extension Hyperliquid {
    /// How a position is margined, or which margining a market allows.
    public struct MarginMode: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// The account's cross margin on the perp DEX backs the position.
        public static let cross = Self(rawValue: "cross")
        /// Margin set aside for the one position backs it.
        public static let isolated = Self(rawValue: "isolated")
        /// A market that allows only isolated margin, which can't be removed from a position.
        public static let strictIsolated = Self(rawValue: "strictIsolated")
        /// A market that allows only isolated margin.
        public static let noCross = Self(rawValue: "noCross")
    }

    /// How an account's spot and perp balances combine.
    ///
    /// In ``unifiedAccount`` and ``portfolioMargin`` mode, the spot balances hold all of the account's
    /// balances and holds; a perp DEX's own margin summary is not meaningful.
    public struct AccountMode: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// One balance per asset, shared by spot and every perp DEX that settles in it.
        public static let unifiedAccount = Self(rawValue: "unifiedAccount")
        /// One portfolio across all eligible assets.
        public static let portfolioMargin = Self(rawValue: "portfolioMargin")
        /// Separate spot and perp balances, with cross margin per perp DEX. Hyperliquid's `"disabled"`.
        public static let standard = Self(rawValue: "disabled")
        /// An account that hasn't chosen a mode. Hyperliquid doesn't document which mode applies.
        public static let `default` = Self(rawValue: "default")
        /// A discontinued mode: USDC defaults to perp balances, other collateral to spot.
        public static let dexAbstraction = Self(rawValue: "dexAbstraction")
    }
}

// MARK: - Market data

extension Hyperliquid.Candle {
    /// How much time one candle covers.
    public struct Interval: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let oneMinute = Self(rawValue: "1m")
        public static let threeMinutes = Self(rawValue: "3m")
        public static let fiveMinutes = Self(rawValue: "5m")
        public static let fifteenMinutes = Self(rawValue: "15m")
        public static let thirtyMinutes = Self(rawValue: "30m")
        public static let oneHour = Self(rawValue: "1h")
        public static let twoHours = Self(rawValue: "2h")
        public static let fourHours = Self(rawValue: "4h")
        public static let eightHours = Self(rawValue: "8h")
        public static let twelveHours = Self(rawValue: "12h")
        public static let oneDay = Self(rawValue: "1d")
        public static let threeDays = Self(rawValue: "3d")
        public static let oneWeek = Self(rawValue: "1w")
        public static let oneMonth = Self(rawValue: "1M")
    }
}

extension Hyperliquid.PredictedFunding {
    /// A venue whose funding Hyperliquid predicts.
    public struct Exchange: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// Hyperliquid's own perpetuals. Hyperliquid's `"HlPerp"`.
        public static let hyperliquid = Self(rawValue: "HlPerp")
        /// Binance's perpetuals. Hyperliquid's `"BinPerp"`.
        public static let binance = Self(rawValue: "BinPerp")
        /// Bybit's perpetuals. Hyperliquid's `"BybitPerp"`.
        public static let bybit = Self(rawValue: "BybitPerp")
    }
}
