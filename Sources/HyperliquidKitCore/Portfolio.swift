public import Foundation

extension Hyperliquid {
    /// An account's value and profit history over several windows.
    public struct Portfolio: Hashable, Sendable {
        /// Each window's history, keyed by window.
        public let histories: [Window: History]

        public init(histories: [Window: History]) {
            self.histories = histories
        }

        public subscript(window: Window) -> History? {
            histories[window]
        }
    }
}

extension Hyperliquid.Portfolio {
    /// The span a history covers, over all markets or perpetuals only.
    public struct Window: RawRepresentable, Hashable, Sendable, Codable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let day = Self(rawValue: "day")
        public static let week = Self(rawValue: "week")
        public static let month = Self(rawValue: "month")
        public static let allTime = Self(rawValue: "allTime")
        public static let perpetualsDay = Self(rawValue: "perpDay")
        public static let perpetualsWeek = Self(rawValue: "perpWeek")
        public static let perpetualsMonth = Self(rawValue: "perpMonth")
        public static let perpetualsAllTime = Self(rawValue: "perpAllTime")
    }

    /// The account's value and profit over one window, oldest first.
    public struct History: Hashable, Sendable {
        public let accountValues: [Sample]
        public let profitAndLoss: [Sample]
        /// The value traded in the window.
        public let volume: Decimal

        public init(accountValues: [Sample], profitAndLoss: [Sample], volume: Decimal) {
            self.accountValues = accountValues
            self.profitAndLoss = profitAndLoss
            self.volume = volume
        }
    }

    /// A value at a time.
    public struct Sample: Hashable, Sendable {
        public let time: Date
        public let value: Decimal

        public init(time: Date, value: Decimal) {
            self.time = time
            self.value = value
        }
    }
}

// MARK: - Wire

extension Hyperliquid.Portfolio: Decodable {
    /// `[[window, history]]`.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var histories: [Window: History] = [:]
        while !container.isAtEnd {
            var pair = try container.nestedUnkeyedContainer()
            let window = try pair.decode(Window.self)
            histories[window] = try pair.decode(History.self)
        }
        self.histories = histories
    }
}

extension Hyperliquid.Portfolio.History: Decodable {
    private enum CodingKeys: String, CodingKey {
        case accountValueHistory, pnlHistory, vlm
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountValues = try container.decode([Hyperliquid.Portfolio.Sample].self, forKey: .accountValueHistory)
        profitAndLoss = try container.decode([Hyperliquid.Portfolio.Sample].self, forKey: .pnlHistory)
        volume = try container.decode(WireDecimal.self, forKey: .vlm).value
    }
}

extension Hyperliquid.Portfolio.Sample: Decodable {
    /// `[time, "value"]`.
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        time = try container.decode(WireDate.self).value
        value = try container.decode(WireDecimal.self).value
    }
}
