import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Vocabulary")
    struct VocabularyTests {
        enum Vocabulary: CaseIterable, Sendable {
            case side, timeInForce, triggerKind, orderStatus, marginMode, accountMode
        }

        @Test(arguments: Vocabulary.allCases)
        func `a value Hyperliquid adds later decodes and encodes back unchanged`(vocabulary: Vocabulary) throws {
            let json = #"["somethingNew"]"#
            #expect(try roundTrip(vocabulary, json) == json)
        }

        // Hyperliquid's spelling of each member, so a mistyped raw value fails here.
        @Test(arguments: [
            (Hyperliquid.Side.buy.rawValue, "B"),
            (Hyperliquid.Side.sell.rawValue, "A"),
            (Hyperliquid.TimeInForce.goodTilCanceled.rawValue, "Gtc"),
            (Hyperliquid.TimeInForce.addLiquidityOnly.rawValue, "Alo"),
            (Hyperliquid.TimeInForce.immediateOrCancel.rawValue, "Ioc"),
            (Hyperliquid.TimeInForce.frontendMarket.rawValue, "FrontendMarket"),
            (Hyperliquid.TimeInForce.liquidationMarket.rawValue, "LiquidationMarket"),
            (Hyperliquid.TriggerKind.takeProfit.rawValue, "tp"),
            (Hyperliquid.TriggerKind.stopLoss.rawValue, "sl"),
            (Hyperliquid.MarginMode.cross.rawValue, "cross"),
            (Hyperliquid.MarginMode.isolated.rawValue, "isolated"),
            (Hyperliquid.MarginMode.strictIsolated.rawValue, "strictIsolated"),
            (Hyperliquid.MarginMode.noCross.rawValue, "noCross"),
            (Hyperliquid.AccountMode.unifiedAccount.rawValue, "unifiedAccount"),
            (Hyperliquid.AccountMode.portfolioMargin.rawValue, "portfolioMargin"),
            (Hyperliquid.AccountMode.standard.rawValue, "disabled"),
            (Hyperliquid.AccountMode.default.rawValue, "default"),
            (Hyperliquid.AccountMode.dexAbstraction.rawValue, "dexAbstraction"),
        ])
        func `each member has Hyperliquid's spelling`(member: String, expected: String) {
            #expect(member == expected)
        }

        // Every order status Hyperliquid documents, in its documented order.
        @Test func `order statuses have Hyperliquid's spelling`() {
            let statuses: [Hyperliquid.OrderStatus] = [
                .open, .filled, .canceled, .triggered, .rejected, .marginCanceled, .vaultWithdrawalCanceled,
                .openInterestCapCanceled, .selfTradeCanceled, .reduceOnlyCanceled, .siblingFilledCanceled,
                .delistedCanceled, .liquidatedCanceled, .scheduledCancel, .tickRejected, .minTradeNotionalRejected,
                .perpMarginRejected, .reduceOnlyRejected, .badAddLiquidityOnlyPriceRejected,
                .immediateOrCancelRejected, .badTriggerPriceRejected, .marketOrderNoLiquidityRejected,
                .positionIncreaseAtOpenInterestCapRejected, .positionFlipAtOpenInterestCapRejected,
                .tooAggressiveAtOpenInterestCapRejected, .openInterestIncreaseRejected,
                .insufficientSpotBalanceRejected, .oracleRejected, .perpMaxPositionRejected,
            ]
            #expect(statuses.map(\.rawValue) == [
                "open", "filled", "canceled", "triggered", "rejected", "marginCanceled", "vaultWithdrawalCanceled",
                "openInterestCapCanceled", "selfTradeCanceled", "reduceOnlyCanceled", "siblingFilledCanceled",
                "delistedCanceled", "liquidatedCanceled", "scheduledCancel", "tickRejected", "minTradeNtlRejected",
                "perpMarginRejected", "reduceOnlyRejected", "badAloPxRejected", "iocCancelRejected",
                "badTriggerPxRejected", "marketOrderNoLiquidityRejected", "positionIncreaseAtOpenInterestCapRejected",
                "positionFlipAtOpenInterestCapRejected", "tooAggressiveAtOpenInterestCapRejected",
                "openInterestIncreaseRejected", "insufficientSpotBalanceRejected", "oracleRejected",
                "perpMaxPositionRejected",
            ])
        }

        private func roundTrip(_ vocabulary: Vocabulary, _ json: String) throws -> String {
            switch vocabulary {
            case .side: try roundTrip(Hyperliquid.Side.self, json)
            case .timeInForce: try roundTrip(Hyperliquid.TimeInForce.self, json)
            case .triggerKind: try roundTrip(Hyperliquid.TriggerKind.self, json)
            case .orderStatus: try roundTrip(Hyperliquid.OrderStatus.self, json)
            case .marginMode: try roundTrip(Hyperliquid.MarginMode.self, json)
            case .accountMode: try roundTrip(Hyperliquid.AccountMode.self, json)
            }
        }

        private func roundTrip<Value: Codable>(_ type: Value.Type, _ json: String) throws -> String {
            let decoded = try JSONDecoder().decode([Value].self, from: Data(json.utf8))
            return String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        }
    }
}
