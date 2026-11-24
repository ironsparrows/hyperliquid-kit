public import Foundation

extension Hyperliquid {
    /// One execution of an account's order.
    ///
    /// An account's fills include spot fills, such as `"@107"`; ``coin``'s ``Coin/kind`` tells them
    /// apart.
    public struct Fill: Hashable, Sendable {
        public let coin: Coin
        public let side: Side
        public let price: Decimal
        /// The filled size, in the base coin.
        public let size: Decimal
        public let time: Date
        /// The position's size, or the spot balance, before the fill.
        public let startPosition: Decimal
        public let direction: Direction
        public let closedPnL: Decimal
        /// The transaction's hash. TWAP slice fills carry the zero hash.
        public let hash: TransactionHash
        public let orderID: OrderID
        /// Whether the order crossed the spread, taking liquidity.
        public let isTaker: Bool
        /// The fee, builder fee included; negative for a rebate.
        public let fee: Decimal
        /// The token the fee was paid in, such as `"USDC"`, when Hyperliquid sends it.
        public let feeToken: String?
        /// The trade's ID, when Hyperliquid sends it.
        public let tradeID: TradeID?
        /// The part of ``fee`` paid to a builder, when there is one.
        public let builderFee: Decimal?
        /// The liquidation the fill was part of, when it was.
        public let liquidation: Liquidation?
        /// The TWAP order the fill belongs to, when Hyperliquid sends one.
        public let twapID: TwapID?

        public init(
            coin: Coin, side: Side, price: Decimal, size: Decimal, time: Date, startPosition: Decimal,
            direction: Direction, closedPnL: Decimal, hash: TransactionHash, orderID: OrderID, isTaker: Bool,
            fee: Decimal, feeToken: String?, tradeID: TradeID?, builderFee: Decimal? = nil,
            liquidation: Liquidation? = nil, twapID: TwapID? = nil
        ) {
            self.coin = coin
            self.side = side
            self.price = price
            self.size = size
            self.time = time
            self.startPosition = startPosition
            self.direction = direction
            self.closedPnL = closedPnL
            self.hash = hash
            self.orderID = orderID
            self.isTaker = isTaker
            self.fee = fee
            self.feeToken = feeToken
            self.tradeID = tradeID
            self.builderFee = builderFee
            self.liquidation = liquidation
            self.twapID = twapID
        }
    }
}

extension Hyperliquid.Fill {
    /// What the fill did to the position, as Hyperliquid writes it for display.
    public struct Direction: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let openLong = Self(rawValue: "Open Long")
        public static let closeLong = Self(rawValue: "Close Long")
        public static let openShort = Self(rawValue: "Open Short")
        public static let closeShort = Self(rawValue: "Close Short")
        /// A spot sell.
        public static let sell = Self(rawValue: "Sell")
        public static let settlement = Self(rawValue: "Settlement")
    }

    /// A liquidation a fill was part of.
    public struct Liquidation: Hashable, Sendable {
        /// The liquidated account, when Hyperliquid sends it.
        public let liquidatedUser: Hyperliquid.Address?
        public let markPrice: Decimal
        public let method: Method

        public init(liquidatedUser: Hyperliquid.Address?, markPrice: Decimal, method: Method) {
            self.liquidatedUser = liquidatedUser
            self.markPrice = markPrice
            self.method = method
        }

        /// How the liquidation was carried out.
        public struct Method: RawRepresentable, Hashable, Sendable, Codable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let market = Self(rawValue: "market")
            public static let backstop = Self(rawValue: "backstop")
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Fill: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coin, side, px, sz, time, startPosition, dir, closedPnl, hash, oid, crossed, fee, feeToken, tid
        case builderFee, liquidation, twapId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            try container.decode(WireDecimal.self, forKey: key).value
        }
        coin = try container.decode(Hyperliquid.Coin.self, forKey: .coin)
        side = try container.decode(Hyperliquid.Side.self, forKey: .side)
        price = try decimal(.px)
        size = try decimal(.sz)
        time = try container.decode(WireDate.self, forKey: .time).value
        startPosition = try decimal(.startPosition)
        direction = try container.decode(Direction.self, forKey: .dir)
        closedPnL = try decimal(.closedPnl)
        hash = try container.decode(Hyperliquid.TransactionHash.self, forKey: .hash)
        orderID = try container.decode(Hyperliquid.OrderID.self, forKey: .oid)
        isTaker = try container.decode(Bool.self, forKey: .crossed)
        fee = try decimal(.fee)
        feeToken = try container.decodeIfPresent(String.self, forKey: .feeToken)
        tradeID = try container.decodeIfPresent(Hyperliquid.TradeID.self, forKey: .tid)
        builderFee = try container.decodeIfPresent(WireDecimal.self, forKey: .builderFee)?.value
        liquidation = try container.decodeIfPresent(Liquidation.self, forKey: .liquidation)
        twapID = try container.decodeIfPresent(Hyperliquid.TwapID.self, forKey: .twapId)
    }
}

extension Hyperliquid.Fill.Liquidation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case liquidatedUser, markPx, method
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liquidatedUser = try container.decodeIfPresent(Hyperliquid.Address.self, forKey: .liquidatedUser)
        markPrice = try container.decode(WireDecimal.self, forKey: .markPx).value
        method = try container.decode(Method.self, forKey: .method)
    }
}
