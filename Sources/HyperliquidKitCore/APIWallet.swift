public import Foundation

extension Hyperliquid {
    /// An API wallet an account has approved to trade for it, with the name it was given.
    public struct APIWallet: Hashable, Sendable {
        public let name: String
        public let address: Address
        /// When the approval expires.
        public let validUntil: Date

        public init(name: String, address: Address, validUntil: Date) {
            self.name = name
            self.address = address
            self.validUntil = validUntil
        }
    }
}

// MARK: - Wire

extension Hyperliquid.APIWallet: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, address, validUntil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(Hyperliquid.Address.self, forKey: .address)
        validUntil = try container.decode(WireDate.self, forKey: .validUntil).value
    }
}
