extension Hyperliquid {
    /// A sub-account of a master account, with its perpetual state and balances.
    public struct SubAccount: Hashable, Sendable {
        public let name: String
        public let address: Address
        public let master: Address
        /// The sub-account's positions and margin.
        public let perpetualState: PerpetualState
        public let balances: [Balance]

        public init(name: String, address: Address, master: Address, perpetualState: PerpetualState, balances: [Balance]) {
            self.name = name
            self.address = address
            self.master = master
            self.perpetualState = perpetualState
            self.balances = balances
        }
    }
}

// MARK: - Wire

extension Hyperliquid.SubAccount: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, subAccountUser, master, clearinghouseState, spotState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(Hyperliquid.Address.self, forKey: .subAccountUser)
        master = try container.decode(Hyperliquid.Address.self, forKey: .master)
        perpetualState = try container.decode(Hyperliquid.PerpetualState.self, forKey: .clearinghouseState)
        balances = try container.decode(SpotState.self, forKey: .spotState).balances
    }
}
