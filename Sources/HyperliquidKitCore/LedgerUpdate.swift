public import Foundation

extension Hyperliquid {
    /// A change to an account's balances other than funding: a deposit, a transfer, a withdrawal, a
    /// liquidation and so on.
    ///
    /// Each kind carries the fields Hyperliquid's websocket subscriptions page documents for it
    /// (`WsLedgerUpdate`), which reads and streams share. A kind this type doesn't model arrives as
    /// ``Change/unknown(kind:)``, so it is never lost.
    public struct LedgerUpdate: Hashable, Sendable {
        public let time: Date
        public let hash: TransactionHash
        public let change: Change

        public init(time: Date, hash: TransactionHash, change: Change) {
            self.time = time
            self.hash = hash
            self.change = change
        }
    }
}

extension Hyperliquid.LedgerUpdate {
    /// What changed. Amounts are as Hyperliquid sends them; on a transfer, `user` sent and
    /// `destination` received.
    ///
    /// Later versions of this type may model more kinds, so give a `switch` over it a `default`.
    public enum Change: Hashable, Sendable {
        case deposit(usdc: Decimal)
        case withdraw(usdc: Decimal, nonce: UInt64, fee: Decimal)
        /// USDC sent between accounts.
        case internalTransfer(usdc: Decimal, user: Hyperliquid.Address, destination: Hyperliquid.Address, fee: Decimal)
        /// USDC moved between an account and its sub-account.
        case subAccountTransfer(usdc: Decimal, user: Hyperliquid.Address, destination: Hyperliquid.Address)
        case liquidation(Liquidation)
        case vaultCreate(vault: Hyperliquid.Address, usdc: Decimal)
        case vaultDeposit(vault: Hyperliquid.Address, usdc: Decimal)
        case vaultDistribution(vault: Hyperliquid.Address, usdc: Decimal)
        case vaultWithdraw(VaultWithdrawal)
        case vaultLeaderCommission(user: Hyperliquid.Address, usdc: Decimal)
        /// A spot token sent between accounts.
        case spotTransfer(SpotTransfer)
        /// USDC moved between the account's spot and perp balances.
        case accountClassTransfer(usdc: Decimal, toPerp: Bool)
        case spotGenesis(token: String, amount: Decimal)
        case rewardsClaim(amount: Decimal)
        /// A change of a kind this type doesn't model, named as Hyperliquid names it, such as
        /// `"send"`. Its fields aren't read.
        case unknown(kind: String)
    }

    /// A liquidation of the account's positions.
    public struct Liquidation: Hashable, Sendable {
        /// The account's value, or for isolated positions the isolated account value.
        public let accountValue: Decimal
        /// ``Hyperliquid/MarginMode/cross`` or ``Hyperliquid/MarginMode/isolated``.
        public let marginMode: Hyperliquid.MarginMode
        public let positions: [Position]

        public init(accountValue: Decimal, marginMode: Hyperliquid.MarginMode, positions: [Position]) {
            self.accountValue = accountValue
            self.marginMode = marginMode
            self.positions = positions
        }

        /// A liquidated position.
        public struct Position: Hashable, Sendable {
            public let coin: Hyperliquid.Coin
            /// The position's size: positive for a long, negative for a short. Hyperliquid's `szi`.
            public let size: Decimal

            public init(coin: Hyperliquid.Coin, size: Decimal) {
                self.coin = coin
                self.size = size
            }
        }
    }

    /// A withdrawal from a vault. Hyperliquid's fields, with its names.
    public struct VaultWithdrawal: Hashable, Sendable {
        public let vault: Hyperliquid.Address
        public let user: Hyperliquid.Address
        /// Hyperliquid's `requestedUsd`.
        public let requestedUSD: Decimal
        public let commission: Decimal
        public let closingCost: Decimal
        public let basis: Decimal
        /// Hyperliquid's `netWithdrawnUsd`.
        public let netWithdrawnUSD: Decimal

        public init(
            vault: Hyperliquid.Address, user: Hyperliquid.Address, requestedUSD: Decimal, commission: Decimal,
            closingCost: Decimal, basis: Decimal, netWithdrawnUSD: Decimal
        ) {
            self.vault = vault
            self.user = user
            self.requestedUSD = requestedUSD
            self.commission = commission
            self.closingCost = closingCost
            self.basis = basis
            self.netWithdrawnUSD = netWithdrawnUSD
        }
    }

    /// A spot token sent from `user` to `destination`.
    public struct SpotTransfer: Hashable, Sendable {
        /// The token's name, such as `"PURR"`.
        public let token: String
        public let amount: Decimal
        /// The amount's value in USDC. Hyperliquid's `usdcValue`.
        public let usdcValue: Decimal
        public let user: Hyperliquid.Address
        public let destination: Hyperliquid.Address
        public let fee: Decimal

        public init(
            token: String, amount: Decimal, usdcValue: Decimal, user: Hyperliquid.Address,
            destination: Hyperliquid.Address, fee: Decimal
        ) {
            self.token = token
            self.amount = amount
            self.usdcValue = usdcValue
            self.user = user
            self.destination = destination
            self.fee = fee
        }
    }
}

// MARK: - Wire

extension Hyperliquid.LedgerUpdate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case time, hash, delta
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(WireDate.self, forKey: .time).value
        hash = try container.decode(Hyperliquid.TransactionHash.self, forKey: .hash)
        change = try container.decode(Change.self, forKey: .delta)
    }
}

extension Hyperliquid.LedgerUpdate.Change: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, usdc, nonce, fee, user, destination, vault, token, amount, usdcValue, toPerp
        case requestedUsd, commission, closingCost, basis, netWithdrawnUsd
    }

    /// `{"type": …, …}`, with the fields its type documents.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            try container.decode(WireDecimal.self, forKey: key).value
        }
        func address(_ key: CodingKeys) throws -> Hyperliquid.Address {
            try container.decode(Hyperliquid.Address.self, forKey: key)
        }
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "deposit":
            self = .deposit(usdc: try decimal(.usdc))
        case "withdraw":
            self = .withdraw(usdc: try decimal(.usdc), nonce: try container.decode(UInt64.self, forKey: .nonce), fee: try decimal(.fee))
        case "internalTransfer":
            self = .internalTransfer(
                usdc: try decimal(.usdc), user: try address(.user), destination: try address(.destination), fee: try decimal(.fee)
            )
        case "subAccountTransfer":
            self = .subAccountTransfer(usdc: try decimal(.usdc), user: try address(.user), destination: try address(.destination))
        case "liquidation":
            self = .liquidation(try Hyperliquid.LedgerUpdate.Liquidation(from: decoder))
        case "vaultCreate":
            self = .vaultCreate(vault: try address(.vault), usdc: try decimal(.usdc))
        case "vaultDeposit":
            self = .vaultDeposit(vault: try address(.vault), usdc: try decimal(.usdc))
        case "vaultDistribution":
            self = .vaultDistribution(vault: try address(.vault), usdc: try decimal(.usdc))
        case "vaultWithdraw":
            self = .vaultWithdraw(.init(
                vault: try address(.vault), user: try address(.user), requestedUSD: try decimal(.requestedUsd),
                commission: try decimal(.commission), closingCost: try decimal(.closingCost), basis: try decimal(.basis),
                netWithdrawnUSD: try decimal(.netWithdrawnUsd)
            ))
        case "vaultLeaderCommission":
            self = .vaultLeaderCommission(user: try address(.user), usdc: try decimal(.usdc))
        case "spotTransfer":
            self = .spotTransfer(.init(
                token: try container.decode(String.self, forKey: .token), amount: try decimal(.amount),
                usdcValue: try decimal(.usdcValue), user: try address(.user), destination: try address(.destination),
                fee: try decimal(.fee)
            ))
        case "accountClassTransfer":
            self = .accountClassTransfer(usdc: try decimal(.usdc), toPerp: try container.decode(Bool.self, forKey: .toPerp))
        case "spotGenesis":
            self = .spotGenesis(token: try container.decode(String.self, forKey: .token), amount: try decimal(.amount))
        case "rewardsClaim":
            self = .rewardsClaim(amount: try decimal(.amount))
        default:
            self = .unknown(kind: type)
        }
    }
}

extension Hyperliquid.LedgerUpdate.Liquidation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case accountValue, leverageType, liquidatedPositions
    }

    private struct WirePosition: Decodable {
        let coin: Hyperliquid.Coin
        let szi: WireDecimal
    }

    /// `leverageType` is `"Cross"` or `"Isolated"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountValue = try container.decode(WireDecimal.self, forKey: .accountValue).value
        let leverageType = try container.decode(String.self, forKey: .leverageType)
        marginMode = Hyperliquid.MarginMode(rawValue: leverageType.prefix(1).lowercased() + leverageType.dropFirst())
        positions = try container.decode([WirePosition].self, forKey: .liquidatedPositions).map {
            Position(coin: $0.coin, size: $0.szi.value)
        }
    }
}
