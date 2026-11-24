extension Hyperliquid {
    /// What an address is to Hyperliquid: an account, an API wallet, a vault, a sub-account, or unknown.
    public struct AccountRole: Hashable, Sendable {
        public let kind: Kind
        /// For an API wallet, the account it trades for; for a sub-account, its master account.
        public let owner: Address?

        public init(kind: Kind, owner: Address? = nil) {
            self.kind = kind
            self.owner = owner
        }
    }
}

extension Hyperliquid.AccountRole {
    /// The kind of address.
    public struct Kind: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// An address Hyperliquid doesn't know.
        public static let missing = Self(rawValue: "missing")
        /// An account.
        public static let user = Self(rawValue: "user")
        /// An API wallet.
        public static let agent = Self(rawValue: "agent")
        public static let vault = Self(rawValue: "vault")
        public static let subAccount = Self(rawValue: "subAccount")
    }
}

// MARK: - Wire

extension Hyperliquid.AccountRole: Decodable {
    private enum CodingKeys: String, CodingKey {
        case role, data
    }

    /// `data` is `{user}` for an API wallet and `{master}` for a sub-account.
    private struct Owner: Decodable {
        let user: Hyperliquid.Address?
        let master: Hyperliquid.Address?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .role)
        let data = try container.decodeIfPresent(Owner.self, forKey: .data)
        owner = data?.user ?? data?.master
    }
}
