import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Account state")
    struct AccountStateTests {
        private let decoder = JSONDecoder()

        private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
            try decoder.decode(type, from: Data(json.utf8))
        }

        // MARK: Perpetual state

        @Test func `a perpetual state without positions decodes on the first and a builder-deployed perp DEX`() throws {
            let state = try decoder.decode(Hyperliquid.PerpetualState.self, from: Fixture.data("clearinghouseState"))
            #expect(state.positions.isEmpty)
            #expect(state.marginSummary.accountValue == Decimal(string: "565.136441"))
            #expect(state.crossMarginSummary.totalRawUSD == Decimal(string: "565.136441"))
            #expect(state.withdrawable == Decimal(string: "565.136441"))
            #expect(state.time == Date(timeIntervalSince1970: 1_795_519_902.721))
            let xyz = try decoder.decode(Hyperliquid.PerpetualState.self, from: Fixture.data("clearinghouseState_xyz"))
            #expect(xyz.marginSummary.accountValue == Decimal(string: "2802.5"))
        }

        @Test func `an isolated position decodes with its leverage, funding and raw USD`() throws {
            let state = try decode(Hyperliquid.PerpetualState.self, Self.documentedState)
            let position = try #require(state.positions.first)
            #expect(position.coin == "ETH")
            #expect(position.size == Decimal(string: "0.0335"))
            #expect(position.leverage == .isolated(20))
            #expect(position.rawUSD == Decimal(string: "-95.059824"))
            #expect(position.entryPrice == Decimal(string: "2986.3"))
            #expect(position.liquidationPrice == Decimal(string: "2866.26936529"))
            #expect(position.maxLeverage == 50)
            #expect(position.cumulativeFunding?.allTime == Decimal(string: "514.085417"))
        }

        @Test func `a state without its time, and a cross position without prices or funding, decode`() throws {
            let json = #"{"assetPositions":[{"position":{"coin":"ETH","entryPx":null,"leverage":{"type":"cross","value":20},"liquidationPx":null,"marginUsed":"11.383755","positionValue":"227.675114","returnOnEquity":"0.01042942","szi":"-0.1334","unrealizedPnl":"0.118726"},"type":"oneWay"}],"crossMarginSummary":{"accountValue":"1","totalMarginUsed":"0","totalNtlPos":"0","totalRawUsd":"1"},"marginSummary":{"accountValue":"1","totalMarginUsed":"0","totalNtlPos":"0","totalRawUsd":"1"},"withdrawable":"1"}"#
            let state = try decode(Hyperliquid.PerpetualState.self, json)
            #expect(state.time == nil)
            #expect(state.crossMaintenanceMarginUsed == nil)
            let position = try #require(state.positions.first)
            #expect(position.leverage == .cross(20))
            #expect(position.size == Decimal(string: "-0.1334"))
            #expect(position.entryPrice == nil)
            #expect(position.liquidationPrice == nil)
            #expect(position.rawUSD == nil)
            #expect(position.maxLeverage == nil)
            #expect(position.cumulativeFunding == nil)
        }

        // MARK: Balances, mode, limits

        @Test func `balances decode, a balance without a token index included`() throws {
            let state = try decoder.decode(SpotState.self, from: Fixture.data("spotClearinghouseState"))
            #expect(state.balances.count == 176)
            #expect(state.balances.first == .init(
                token: "USDC", tokenIndex: 0, total: Decimal(string: "1019.97983005")!, hold: 0, entryNotional: 0
            ))
            let outcome = try decode(Hyperliquid.Balance.self, #"{"coin":"+1230","hold":"0.0","total":"25.0","entryNtl":"12.5"}"#)
            #expect(outcome.tokenIndex == nil)
        }

        @Test func `the account mode decodes`() throws {
            #expect(try decoder.decode(Hyperliquid.AccountMode.self, from: Fixture.data("userAbstraction")) == .default)
        }

        @Test func `trading limits decode with both pairs in Hyperliquid's order`() throws {
            let limits = try decoder.decode(Hyperliquid.TradingLimits.self, from: Fixture.data("activeAssetData"))
            #expect(limits.coin == "BTC")
            #expect(limits.leverage == .cross(20))
            #expect(limits.maxTradeSizes == [0, 0])
            #expect(limits.markPrice == Decimal(59880))
            let isolated = try decode(
                Hyperliquid.TradingLimits.self,
                #"{"user":"0x0000000000000000000000000000000000000000","coin":"xyz:XYZ100","leverage":{"type":"isolated","value":20,"rawUsd":"0.0"},"maxTradeSzs":["1.5","2.5"],"availableToTrade":["3.0","4.0"],"markPx":"25451.0"}"#
            )
            #expect(isolated.leverage == .isolated(20))
            #expect(isolated.rawUSD == 0)
            #expect(isolated.maxTradeSizes == [Decimal(string: "1.5")!, Decimal(string: "2.5")!])
            #expect(isolated.availableToTrade == [3, 4])
        }

        // MARK: Fees and limits

        @Test func `fees decode with their daily volumes and schedule`() throws {
            let fees = try decoder.decode(Hyperliquid.Fees.self, from: Fixture.data("userFees"))
            #expect(fees.takerRate == Decimal(string: "0.0004"))
            #expect(fees.makerRate == Decimal(string: "0.00012"))
            #expect(fees.spotTakerRate == Decimal(string: "0.0006"))
            #expect(fees.stakingDiscount == 0)
            #expect(fees.dailyVolumes.count == 15)
            #expect(fees.dailyVolumes.first?.day == DateComponents(year: 2026, month: 11, day: 10))
            #expect(fees.dailyVolumes.first?.exchange == Decimal(string: "7747473759.0100002289"))
            #expect(fees.schedule.takerRate == Decimal(string: "0.00045"))
            #expect(fees.schedule.volumeTiers.count == 6)
            #expect(fees.schedule.volumeTiers.first?.notionalCutoff == Decimal(5_000_000))
            #expect(fees.schedule.marketMakerTiers.first == .init(
                makerFractionCutoff: Decimal(string: "0.005")!, makerRate: Decimal(string: "-0.00001")!
            ))
            #expect(fees.schedule.stakingDiscountTiers.count == 7)
        }

        @Test func `a day that isn't year-month-day fails to decode`() {
            #expect(throws: DecodingError.self) {
                try decode(Hyperliquid.Fees.DailyVolume.self, #"{"date":"23/05/2025","userCross":"0","userAdd":"0","exchange":"0"}"#)
            }
        }

        @Test func `a rate limit without a surplus decodes`() throws {
            let limit = try decode(
                Hyperliquid.RateLimit.self,
                #"{"cumVlm":"170043721737.450012207","nRequestsUsed":36589831368,"nRequestsCap":170043731737}"#
            )
            #expect(limit.requestsUsed == 36_589_831_368)
            #expect(limit.requestsSurplus == nil)
        }

        @Test func `the rate limit decodes`() throws {
            let limit = try decoder.decode(Hyperliquid.RateLimit.self, from: Fixture.data("userRateLimit"))
            #expect(limit == .init(
                cumulativeVolume: Decimal(string: "151392758.400000006")!, requestsUsed: 0, requestsCap: 151_402_758,
                requestsSurplus: 0
            ))
        }

        // MARK: Related addresses

        @Test(arguments: [
            (#"{"role":"user"}"#, Hyperliquid.AccountRole(kind: .user)),
            (#"{"role":"missing"}"#, .init(kind: .missing)),
            (#"{"role":"vault"}"#, .init(kind: .vault)),
            (#"{"role":"agent","data":{"user":"0x00000000000000000000000000000000000000b2"}}"#,
             .init(kind: .agent, owner: "0x00000000000000000000000000000000000000b2")),
            (#"{"role":"subAccount","data":{"master":"0x00000000000000000000000000000000000000b2"}}"#,
             .init(kind: .subAccount, owner: "0x00000000000000000000000000000000000000b2")),
        ])
        func `each role decodes with its owner`(json: String, role: Hyperliquid.AccountRole) throws {
            #expect(try decode(Hyperliquid.AccountRole.self, json) == role)
        }

        @Test func `the recorded role decodes`() throws {
            #expect(try decoder.decode(Hyperliquid.AccountRole.self, from: Fixture.data("userRole")).kind == .user)
        }

        @Test func `a sub-account decodes with its perpetual state and balances`() throws {
            let accounts = try decode([Hyperliquid.SubAccount].self, Self.documentedSubAccounts)
            let account = try #require(accounts.first)
            #expect(account.name == "Test")
            #expect(account.address.description == "0x00000000000000000000000000000000000000a1")
            #expect(account.master.description == "0x00000000000000000000000000000000000000b2")
            #expect(account.perpetualState.withdrawable == Decimal(string: "29.78001"))
            #expect(account.balances.map(\.token) == ["USDC"])
        }

        @Test func `API wallets decode with their expiry`() throws {
            let wallets = try decode(
                [Hyperliquid.APIWallet].self,
                #"[{"name":"ok","address":"0x00000000000000000000000000000000000000a1","validUntil":1767776120478},{"name":"new","address":"0x00000000000000000000000000000000000000b2","validUntil":1771174068515}]"#
            )
            #expect(wallets.map(\.name) == ["ok", "new"])
            #expect(wallets.first?.validUntil == Date(timeIntervalSince1970: 1_767_776_120.478))
        }

        // MARK: History

        @Test func `the portfolio decodes every window`() throws {
            let portfolio = try decoder.decode(Hyperliquid.Portfolio.self, from: Fixture.data("portfolio"))
            #expect(Set(portfolio.histories.keys) == [
                .day, .week, .month, .allTime, .perpetualsDay, .perpetualsWeek, .perpetualsMonth, .perpetualsAllTime,
            ])
            let day = try #require(portfolio[.day])
            #expect(day.accountValues.count == 13)
            #expect(day.accountValues.first == .init(
                time: Date(timeIntervalSince1970: 1_795_432_320.015), value: Decimal(string: "46708520.079125002")!
            ))
            #expect(day.volume == 0)
        }

        @Test func `funding payments decode with a null sample count`() throws {
            let payments = try decode(
                [Hyperliquid.FundingPayment].self,
                #"[{"delta":{"coin":"ETH","fundingRate":"0.0000417","szi":"49.1477","type":"funding","usdc":"-3.625312","nSamples":null},"hash":"0xa166e3fa63c25663024b03f2e0da011a00307e4017465df020210d3d432e7cb8","time":1681222254710}]"#
            )
            #expect(payments == [.init(
                time: Date(timeIntervalSince1970: 1_681_222_254.71),
                hash: .init(rawValue: "0xa166e3fa63c25663024b03f2e0da011a00307e4017465df020210d3d432e7cb8"),
                coin: "ETH", usdc: Decimal(string: "-3.625312")!, positionSize: Decimal(string: "49.1477")!,
                rate: Decimal(string: "0.0000417")!
            )])
        }

        @Test func `a funding payment decodes its sample count`() throws {
            let payment = try decode(
                Hyperliquid.FundingPayment.self,
                #"{"delta":{"coin":"APE","fundingRate":"-0.00029319","nSamples":3,"szi":"40.13333333","type":"funding","usdc":"0.145796"},"hash":"0x0000000000000000000000000000000000000000000000000000000000000001","time":1681948800000}"#
            )
            #expect(payment.sampleCount == 3)
            #expect(payment.usdc == Decimal(string: "0.145796"))
        }

        @Test func `deposits and account class transfers decode with their USDC`() throws {
            let updates = try decode(
                [Hyperliquid.LedgerUpdate].self,
                #"[{"time":1731999196516,"hash":"0x0000000000000000000000000000000000000000000000000000000000000001","delta":{"type":"deposit","usdc":"2703997.4500000002"}},{"time":1732834706761,"hash":"0x0000000000000000000000000000000000000000000000000000000000000002","delta":{"type":"accountClassTransfer","usdc":"12.0","toPerp":false}}]"#
            )
            #expect(updates.map(\.kind) == [.deposit, .accountClassTransfer])
            #expect(updates.map(\.usdc) == [Decimal(string: "2703997.4500000002"), 12])
        }

        @Test func `ledger updates decode their kind, and USDC where they move it`() throws {
            let updates = try decoder.decode([Hyperliquid.LedgerUpdate].self, from: Fixture.data("userNonFundingLedgerUpdates"))
            #expect(updates.map(\.kind) == [
                .internalTransfer, .internalTransfer, .internalTransfer, .internalTransfer, .internalTransfer,
                .spotTransfer, .spotTransfer, .spotGenesis,
            ])
            #expect(updates.first?.usdc == 1)
            #expect(updates.last?.usdc == nil)
        }

        // MARK: Documented examples

        private static let documentedState = #"{"assetPositions":[{"position":{"coin":"ETH","cumFunding":{"allTime":"514.085417","sinceChange":"0.0","sinceOpen":"0.0"},"entryPx":"2986.3","leverage":{"rawUsd":"-95.059824","type":"isolated","value":20},"liquidationPx":"2866.26936529","marginUsed":"4.967826","maxLeverage":50,"positionValue":"100.02765","returnOnEquity":"-0.0026789","szi":"0.0335","unrealizedPnl":"-0.0134"},"type":"oneWay"}],"crossMaintenanceMarginUsed":"0.0","crossMarginSummary":{"accountValue":"13104.514502","totalMarginUsed":"0.0","totalNtlPos":"0.0","totalRawUsd":"13104.514502"},"marginSummary":{"accountValue":"13109.482328","totalMarginUsed":"4.967826","totalNtlPos":"100.02765","totalRawUsd":"13009.454678"},"time":1708622398623,"withdrawable":"13104.514502"}"#

        private static let documentedSubAccounts = #"[{"name":"Test","subAccountUser":"0x00000000000000000000000000000000000000a1","master":"0x00000000000000000000000000000000000000b2","clearinghouseState":{"marginSummary":{"accountValue":"29.78001","totalNtlPos":"0.0","totalRawUsd":"29.78001","totalMarginUsed":"0.0"},"crossMarginSummary":{"accountValue":"29.78001","totalNtlPos":"0.0","totalRawUsd":"29.78001","totalMarginUsed":"0.0"},"crossMaintenanceMarginUsed":"0.0","withdrawable":"29.78001","assetPositions":[],"time":1733968369395},"spotState":{"balances":[{"coin":"USDC","token":0,"total":"0.22","hold":"0.0","entryNtl":"0.0"}]}}]"#
    }
}
