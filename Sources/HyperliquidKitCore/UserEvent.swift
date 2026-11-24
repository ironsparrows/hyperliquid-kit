public import Foundation

extension Hyperliquid {
    /// Something that happened to an account besides an order update: fills, a funding payment, a
    /// liquidation, or orders the account didn't cancel itself.
    ///
    /// An event of a kind this type doesn't model arrives as ``unknown(kind:)``, so it is never lost;
    /// later versions of this type may model it with a case of its own, so give a `switch` over it a
    /// `default`.
    public enum UserEvent: Hashable, Sendable {
        /// Fills of the account's orders.
        case fills([Fill])
        /// A funding payment on one of the account's positions; stream payments carry no hash.
        case funding(FundingPayment)
        case liquidation(Liquidation)
        /// Orders canceled by Hyperliquid rather than by the account. Hyperliquid's `nonUserCancel`.
        case nonUserCancel([OrderReference])
        /// An event of a kind this type doesn't model, named as Hyperliquid names it, such as
        /// `"somethingNew"` for `{"somethingNew": …}`. Its contents aren't read.
        case unknown(kind: String)
    }
}

extension Hyperliquid.UserEvent {
    /// A liquidation of the account.
    public struct Liquidation: Hashable, Sendable {
        /// Hyperliquid's `lid`.
        public let id: Hyperliquid.LiquidationID
        public let liquidator: Hyperliquid.Address
        public let liquidatedUser: Hyperliquid.Address
        /// Hyperliquid's `liquidated_ntl_pos`.
        public let positionNotional: Decimal
        /// Hyperliquid's `liquidated_account_value`.
        public let accountValue: Decimal

        public init(
            id: Hyperliquid.LiquidationID, liquidator: Hyperliquid.Address, liquidatedUser: Hyperliquid.Address, positionNotional: Decimal,
            accountValue: Decimal
        ) {
            self.id = id
            self.liquidator = liquidator
            self.liquidatedUser = liquidatedUser
            self.positionNotional = positionNotional
            self.accountValue = accountValue
        }
    }
}

// MARK: - Wire

extension Hyperliquid.UserEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case fills, funding, liquidation, nonUserCancel
    }

    /// The name of any field, for reading kinds this type doesn't model.
    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// An object with one field: `{"fills": […]}`, `{"funding": …}`, `{"liquidation": …}`,
    /// `{"nonUserCancel": […]}`, or any other field as ``unknown(kind:)``.
    ///
    /// - Throws: `DecodingError` for data that isn't an object, an object without exactly one field,
    ///   or a documented kind whose contents don't read.
    public init(from decoder: any Decoder) throws {
        let events = try Self.all(from: decoder)
        guard events.count == 1, let event = events.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "An account event has one field, not \(events.count)")
            )
        }
        self = event
    }

    /// One event per field of an object: the documented kinds first, in the order of the cases, then
    /// the others by name.
    ///
    /// - Throws: `DecodingError` for data that isn't an object, an object without fields, or a
    ///   documented kind whose contents don't read.
    package static func all(from decoder: any Decoder) throws -> [Self] {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var events: [Self] = []
        if container.contains(.fills) {
            events.append(.fills(try container.decode([Hyperliquid.Fill].self, forKey: .fills)))
        }
        if container.contains(.funding) {
            events.append(.funding(try container.decode(Hyperliquid.FundingPayment.self, forKey: .funding)))
        }
        if container.contains(.liquidation) {
            events.append(.liquidation(try container.decode(Liquidation.self, forKey: .liquidation)))
        }
        if container.contains(.nonUserCancel) {
            events.append(.nonUserCancel(try container.decode([Hyperliquid.OrderReference].self, forKey: .nonUserCancel)))
        }
        let others = try decoder.container(keyedBy: Field.self).allKeys.map(\.stringValue)
            .filter { CodingKeys(stringValue: $0) == nil }.sorted()
        events += others.map { .unknown(kind: $0) }
        guard !events.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "An account event without a kind")
            )
        }
        return events
    }
}

extension Hyperliquid.UserEvent.Liquidation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case lid, liquidator
        case liquidatedUser = "liquidated_user"
        case liquidatedNotionalPosition = "liquidated_ntl_pos"
        case liquidatedAccountValue = "liquidated_account_value"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Hyperliquid.LiquidationID.self, forKey: .lid)
        liquidator = try container.decode(Hyperliquid.Address.self, forKey: .liquidator)
        liquidatedUser = try container.decode(Hyperliquid.Address.self, forKey: .liquidatedUser)
        positionNotional = try container.decode(WireDecimal.self, forKey: .liquidatedNotionalPosition).value
        accountValue = try container.decode(WireDecimal.self, forKey: .liquidatedAccountValue).value
    }
}
