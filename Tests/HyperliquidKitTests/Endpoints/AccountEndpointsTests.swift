import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Account and position endpoints")
    struct AccountEndpointsTests {
        private static let account: Hyperliquid.Address = "0x00000000000000000000000000000000000000a1"
        private static let other: Hyperliquid.Address = "0x00000000000000000000000000000000000000b2"
        private static let state = #"{"marginSummary":{"accountValue":"1","totalNtlPos":"0","totalRawUsd":"1","totalMarginUsed":"0"},"crossMarginSummary":{"accountValue":"1","totalNtlPos":"0","totalRawUsd":"1","totalMarginUsed":"0"},"crossMaintenanceMarginUsed":"0","withdrawable":"1","assetPositions":[],"time":1795519902721}"#
        private static let btcMeta = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":40}],"marginTables":[]}"#

        // MARK: The account

        @Test func `a read without an address uses the client's account`() async throws {
            let transport = FakeTransport(json: Self.state)
            _ = try await Self.account(transport).perpetualState()
            #expect(await transport.bodies == [
                #"{"type":"clearinghouseState","user":"0x00000000000000000000000000000000000000a1","dex":""}"#
            ])
        }

        @Test func `an address given to a read wins over the client's account`() async throws {
            let transport = FakeTransport(json: Self.state)
            _ = try await Self.account(transport).perpetualState(dex: .named("xyz"), for: Self.other)
            #expect(await transport.bodies == [
                #"{"type":"clearinghouseState","user":"0x00000000000000000000000000000000000000b2","dex":"xyz"}"#
            ])
        }

        @Test func `a read without an address on a client without an account throws missing account unsent`() async {
            let transport = FakeTransport()
            let account = AccountEndpoints(info: .test(transport), account: nil)
            let position = PositionEndpoints.test(transport)
            await #expect {
                _ = try await account.balances()
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .missingAccount
            }
            await #expect {
                _ = try await position.tradingLimits("BTC")
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .missingAccount
            }
            await #expect {
                _ = try await position.fundingPayments(from: .now)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .missingAccount
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `the client's account reaches account and position reads`() async throws {
            let transport = FakeTransport(responses: [.json(#""default""#), .json("[]")])
            let client = Hyperliquid.Client(account: Self.account, configuration: .init(), transport: transport)
            #expect(try await client.account.mode() == .default)
            _ = try await client.position.fundingPayments(from: Date(timeIntervalSince1970: 1_795_500_000))
            #expect(await transport.bodies == [
                #"{"type":"userAbstraction","user":"0x00000000000000000000000000000000000000a1"}"#,
                #"{"type":"userFunding","user":"0x00000000000000000000000000000000000000a1","startTime":1795500000000}"#,
            ])
        }

        // MARK: Bodies

        @Test func `each account read sends its type and the user`() async throws {
            let user = #""user":"0x00000000000000000000000000000000000000a1""#
            let transport = FakeTransport(responses: [
                .json(#"{"balances":[]}"#),
                .json(#"{"dailyUserVlm":[],"feeSchedule":{"cross":"0.00045","add":"0.00015","referralDiscount":"0.04","tiers":{"vip":[],"mm":[]}},"userCrossRate":"0.0004","userAddRate":"0.00012","activeReferralDiscount":"0.0"}"#),
                .json(#"{"cumVlm":"1","nRequestsUsed":0,"nRequestsCap":10001,"nRequestsSurplus":0}"#),
                .json(#"{"role":"user"}"#),
                .json("[]"),
                .json("[]"),
            ])
            let account = Self.account(transport)
            #expect(try await account.balances().isEmpty)
            #expect(try await account.fees().spotTakerRate == nil)
            #expect(try await account.rateLimit().requestsCap == 10001)
            #expect(try await account.role().kind == .user)
            #expect(try await account.apiWallets().isEmpty)
            #expect(try await account.portfolio().histories.isEmpty)
            #expect(await transport.bodies == [
                "{\"type\":\"spotClearinghouseState\",\(user)}", "{\"type\":\"userFees\",\(user)}",
                "{\"type\":\"userRateLimit\",\(user)}", "{\"type\":\"userRole\",\(user)}",
                "{\"type\":\"extraAgents\",\(user)}", "{\"type\":\"portfolio\",\(user)}",
            ])
        }

        @Test func `sub-accounts are empty when Hyperliquid answers null`() async throws {
            let transport = FakeTransport(json: "null")
            #expect(try await Self.account(transport).subAccounts().isEmpty)
            #expect(await transport.bodies == [#"{"type":"subAccounts","user":"0x00000000000000000000000000000000000000a1"}"#])
        }

        @Test func `the ledger sends a null end time when there is none`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let account = Self.account(transport)
            let start = Date(timeIntervalSince1970: 1_795_500_000)
            _ = try await account.ledger(from: start)
            _ = try await account.ledger(from: start, to: start.addingTimeInterval(1))
            #expect(await transport.bodies == [
                #"{"type":"userNonFundingLedgerUpdates","user":"0x00000000000000000000000000000000000000a1","startTime":1795500000000,"endTime":null}"#,
                #"{"type":"userNonFundingLedgerUpdates","user":"0x00000000000000000000000000000000000000a1","startTime":1795500000000,"endTime":1795500001000}"#,
            ])
        }

        @Test func `funding payments leave out the end time when there is none`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let position = Self.position(transport)
            let start = Date(timeIntervalSince1970: 1_795_500_000)
            _ = try await position.fundingPayments(from: start, for: Self.other)
            _ = try await position.fundingPayments(from: start, to: start.addingTimeInterval(3600))
            #expect(await transport.bodies == [
                #"{"type":"userFunding","user":"0x00000000000000000000000000000000000000b2","startTime":1795500000000}"#,
                #"{"type":"userFunding","user":"0x00000000000000000000000000000000000000a1","startTime":1795500000000,"endTime":1795503600000}"#,
            ])
        }

        @Test func `trading limits check the coin, then send the user and coin`() async throws {
            let limits = #"{"user":"0x00000000000000000000000000000000000000a1","coin":"BTC","leverage":{"type":"cross","value":20},"maxTradeSzs":["0.0","0.0"],"availableToTrade":["0.0","0.0"],"markPx":"59880.0"}"#
            let transport = FakeTransport(responses: [.json(Self.btcMeta), .json(limits)])
            let position = Self.position(transport)
            #expect(try await position.tradingLimits("BTC").leverage == .cross(20))
            await #expect {
                _ = try await position.tradingLimits("NOPE")
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unknownCoin
            }
            #expect(await transport.bodies == [
                #"{"type":"meta","dex":""}"#,
                #"{"type":"activeAssetData","user":"0x00000000000000000000000000000000000000a1","coin":"BTC"}"#,
            ])
        }

        @Test(arguments: ["@107", "#10"] as [Hyperliquid.Coin])
        func `trading limits for a spot or outcome coin throw unsupported market without a request`(
            coin: Hyperliquid.Coin
        ) async {
            let transport = FakeTransport()
            await #expect {
                _ = try await Self.position(transport).tradingLimits(coin)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
            }
            #expect(await transport.requests.isEmpty)
        }

        private static func account(_ transport: FakeTransport) -> AccountEndpoints {
            AccountEndpoints(info: .test(transport), account: Self.account)
        }

        private static func position(_ transport: FakeTransport) -> PositionEndpoints {
            PositionEndpoints.test(transport, account: Self.account)
        }
    }
}
