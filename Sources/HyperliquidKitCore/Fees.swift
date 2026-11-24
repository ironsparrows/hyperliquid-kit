public import Foundation

extension Hyperliquid {
    /// An account's fee rates, discounts and recent daily volume.
    ///
    /// Rates are fractions of the traded value: `0.00045` is 0.045 %. Taker rates apply to orders that
    /// cross the book, maker rates to orders that add liquidity. Spot rates are `nil` when Hyperliquid
    /// doesn't send them.
    public struct Fees: Hashable, Sendable {
        /// The account's perpetual taker rate. Hyperliquid's `userCrossRate`.
        public let takerRate: Decimal
        /// The account's perpetual maker rate. Hyperliquid's `userAddRate`.
        public let makerRate: Decimal
        public let spotTakerRate: Decimal?
        public let spotMakerRate: Decimal?
        /// The referral discount the account receives.
        public let referralDiscount: Decimal
        /// The staking discount the account receives, when Hyperliquid sends one.
        public let stakingDiscount: Decimal?
        /// The account's and the exchange's traded value per day, oldest first.
        public let dailyVolumes: [DailyVolume]
        /// The rates for every tier.
        public let schedule: Schedule

        public init(
            takerRate: Decimal, makerRate: Decimal, spotTakerRate: Decimal?, spotMakerRate: Decimal?,
            referralDiscount: Decimal, stakingDiscount: Decimal?, dailyVolumes: [DailyVolume], schedule: Schedule
        ) {
            self.takerRate = takerRate
            self.makerRate = makerRate
            self.spotTakerRate = spotTakerRate
            self.spotMakerRate = spotMakerRate
            self.referralDiscount = referralDiscount
            self.stakingDiscount = stakingDiscount
            self.dailyVolumes = dailyVolumes
            self.schedule = schedule
        }
    }
}

extension Hyperliquid.Fees {
    /// One day's traded value.
    public struct DailyVolume: Hashable, Sendable {
        /// The day's year, month and day, as Hyperliquid writes it (`"2025-05-23"`).
        public let day: DateComponents
        /// The account's taker volume. Hyperliquid's `userCross`.
        public let taker: Decimal
        /// The account's maker volume. Hyperliquid's `userAdd`.
        public let maker: Decimal
        /// The whole exchange's volume.
        public let exchange: Decimal

        public init(day: DateComponents, taker: Decimal, maker: Decimal, exchange: Decimal) {
            self.day = day
            self.taker = taker
            self.maker = maker
            self.exchange = exchange
        }
    }

    /// The base rates, the tiers that lower them, and the discounts.
    public struct Schedule: Hashable, Sendable {
        public let takerRate: Decimal
        public let makerRate: Decimal
        public let spotTakerRate: Decimal?
        public let spotMakerRate: Decimal?
        public let referralDiscount: Decimal
        /// Rates by volume.
        public let volumeTiers: [VolumeTier]
        /// Maker rates by share of the exchange's maker volume.
        public let marketMakerTiers: [MarketMakerTier]
        /// Discounts by share of staked supply; empty when Hyperliquid sends none.
        public let stakingDiscountTiers: [StakingDiscountTier]

        public init(
            takerRate: Decimal, makerRate: Decimal, spotTakerRate: Decimal?, spotMakerRate: Decimal?,
            referralDiscount: Decimal, volumeTiers: [VolumeTier], marketMakerTiers: [MarketMakerTier],
            stakingDiscountTiers: [StakingDiscountTier] = []
        ) {
            self.takerRate = takerRate
            self.makerRate = makerRate
            self.spotTakerRate = spotTakerRate
            self.spotMakerRate = spotMakerRate
            self.referralDiscount = referralDiscount
            self.volumeTiers = volumeTiers
            self.marketMakerTiers = marketMakerTiers
            self.stakingDiscountTiers = stakingDiscountTiers
        }
    }

    /// The rates from a volume upward. Hyperliquid's `vip` tier.
    public struct VolumeTier: Hashable, Sendable {
        /// The volume the tier starts at. Hyperliquid's `ntlCutoff`.
        public let notionalCutoff: Decimal
        public let takerRate: Decimal
        public let makerRate: Decimal
        public let spotTakerRate: Decimal?
        public let spotMakerRate: Decimal?

        public init(
            notionalCutoff: Decimal, takerRate: Decimal, makerRate: Decimal, spotTakerRate: Decimal? = nil,
            spotMakerRate: Decimal? = nil
        ) {
            self.notionalCutoff = notionalCutoff
            self.takerRate = takerRate
            self.makerRate = makerRate
            self.spotTakerRate = spotTakerRate
            self.spotMakerRate = spotMakerRate
        }
    }

    /// A maker rate from a share of maker volume upward. Hyperliquid's `mm` tier.
    public struct MarketMakerTier: Hashable, Sendable {
        /// Hyperliquid's `makerFractionCutoff`.
        public let makerFractionCutoff: Decimal
        public let makerRate: Decimal

        public init(makerFractionCutoff: Decimal, makerRate: Decimal) {
            self.makerFractionCutoff = makerFractionCutoff
            self.makerRate = makerRate
        }
    }

    /// A fee discount from a share of staked supply upward.
    public struct StakingDiscountTier: Hashable, Sendable {
        /// Hyperliquid's `bpsOfMaxSupply`.
        public let basisPointsOfMaxSupply: Decimal
        public let discount: Decimal

        public init(basisPointsOfMaxSupply: Decimal, discount: Decimal) {
            self.basisPointsOfMaxSupply = basisPointsOfMaxSupply
            self.discount = discount
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Fees: Decodable {
    private enum CodingKeys: String, CodingKey {
        case userCrossRate, userAddRate, userSpotCrossRate, userSpotAddRate, activeReferralDiscount
        case activeStakingDiscount, dailyUserVlm, feeSchedule
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takerRate = try container.decode(WireDecimal.self, forKey: .userCrossRate).value
        makerRate = try container.decode(WireDecimal.self, forKey: .userAddRate).value
        spotTakerRate = try container.decodeIfPresent(WireDecimal.self, forKey: .userSpotCrossRate)?.value
        spotMakerRate = try container.decodeIfPresent(WireDecimal.self, forKey: .userSpotAddRate)?.value
        referralDiscount = try container.decode(WireDecimal.self, forKey: .activeReferralDiscount).value
        stakingDiscount = try container.decodeIfPresent(StakingDiscountTier.self, forKey: .activeStakingDiscount)?
            .discount
        dailyVolumes = try container.decode([DailyVolume].self, forKey: .dailyUserVlm)
        schedule = try container.decode(Schedule.self, forKey: .feeSchedule)
    }
}

extension Hyperliquid.Fees.DailyVolume: Decodable {
    private enum CodingKeys: String, CodingKey {
        case date, userCross, userAdd, exchange
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .date)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .date, in: container, debugDescription: "Not a yyyy-MM-dd day: \(text)"
            )
        }
        day = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        taker = try container.decode(WireDecimal.self, forKey: .userCross).value
        maker = try container.decode(WireDecimal.self, forKey: .userAdd).value
        exchange = try container.decode(WireDecimal.self, forKey: .exchange).value
    }
}

extension Hyperliquid.Fees.Schedule: Decodable {
    private enum CodingKeys: String, CodingKey {
        case cross, add, spotCross, spotAdd, referralDiscount, tiers, stakingDiscountTiers
    }

    private struct Tiers: Decodable {
        let vip: [Hyperliquid.Fees.VolumeTier]
        let mm: [Hyperliquid.Fees.MarketMakerTier]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takerRate = try container.decode(WireDecimal.self, forKey: .cross).value
        makerRate = try container.decode(WireDecimal.self, forKey: .add).value
        spotTakerRate = try container.decodeIfPresent(WireDecimal.self, forKey: .spotCross)?.value
        spotMakerRate = try container.decodeIfPresent(WireDecimal.self, forKey: .spotAdd)?.value
        referralDiscount = try container.decode(WireDecimal.self, forKey: .referralDiscount).value
        let tiers = try container.decode(Tiers.self, forKey: .tiers)
        volumeTiers = tiers.vip
        marketMakerTiers = tiers.mm
        stakingDiscountTiers =
            try container.decodeIfPresent([Hyperliquid.Fees.StakingDiscountTier].self, forKey: .stakingDiscountTiers)
            ?? []
    }
}

extension Hyperliquid.Fees.VolumeTier: Decodable {
    private enum CodingKeys: String, CodingKey {
        case ntlCutoff, cross, add, spotCross, spotAdd
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notionalCutoff = try container.decode(WireDecimal.self, forKey: .ntlCutoff).value
        takerRate = try container.decode(WireDecimal.self, forKey: .cross).value
        makerRate = try container.decode(WireDecimal.self, forKey: .add).value
        spotTakerRate = try container.decodeIfPresent(WireDecimal.self, forKey: .spotCross)?.value
        spotMakerRate = try container.decodeIfPresent(WireDecimal.self, forKey: .spotAdd)?.value
    }
}

extension Hyperliquid.Fees.MarketMakerTier: Decodable {
    private enum CodingKeys: String, CodingKey {
        case makerFractionCutoff, add
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        makerFractionCutoff = try container.decode(WireDecimal.self, forKey: .makerFractionCutoff).value
        makerRate = try container.decode(WireDecimal.self, forKey: .add).value
    }
}

extension Hyperliquid.Fees.StakingDiscountTier: Decodable {
    private enum CodingKeys: String, CodingKey {
        case bpsOfMaxSupply, discount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basisPointsOfMaxSupply = try container.decode(WireDecimal.self, forKey: .bpsOfMaxSupply).value
        discount = try container.decode(WireDecimal.self, forKey: .discount).value
    }
}
