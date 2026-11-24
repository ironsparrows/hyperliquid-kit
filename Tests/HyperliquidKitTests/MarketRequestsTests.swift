import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Market requests")
    struct MarketRequestsTests {
        private static let btcMeta = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":40}],"marginTables":[],"collateralToken":0}"#
        private static let xyzMeta = #"{"universe":[{"name":"xyz:XYZ100","szDecimals":4,"maxLeverage":30,"marginTableId":30}],"marginTables":[],"collateralToken":0}"#
        private static let perpDexs = #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#
        private static let ethMeta = #"{"universe":[{"name":"ETH","szDecimals":4,"maxLeverage":25,"marginTableId":25}],"marginTables":[]}"#
        private static let context = #"{"funding":"0.0000125","openInterest":"688.11","prevDayPx":"15.322","dayNtlVlm":"1169046.29406","premium":null,"oraclePx":"14.32","markPx":"14.3161","midPx":null,"impactPxs":null,"dayBaseVlm":"81000.5"}"#

        @Test func `perpetuals read the perp DEX's meta`() async throws {
            let transport = FakeTransport(json: Self.btcMeta)
            let perpetuals = try await Self.market(transport).perpetuals()
            #expect(perpetuals.map(\.coin) == ["BTC"])
            #expect(await transport.bodies == [#"{"type":"meta","dex":""}"#])
        }

        @Test func `each perpetual is paired with the context in the same position`() async throws {
            let transport = FakeTransport(json: "[" + Self.btcMeta + ",[" + Self.context + "]]")
            let pairs = try await Self.market(transport).perpetualContexts(dex: .named("xyz"))
            #expect(pairs.count == 1)
            #expect(pairs.first?.perpetual.coin == "BTC")
            #expect(pairs.first?.context.markPrice == Decimal(string: "14.3161"))
            #expect(pairs.first?.context.impactBidPrice == nil)
            #expect(await transport.bodies == [#"{"type":"metaAndAssetCtxs","dex":"xyz"}"#])
        }

        @Test func `a context count that doesn't match the perpetuals throws an unexpected response`() async {
            let transport = FakeTransport(json: "[" + Self.btcMeta + ",[]]")
            await #expect {
                try await Self.market(transport).perpetualContexts()
            } throws: { error in
                (error as? HyperliquidError)?.kind == .unexpectedResponse
            }
        }

        @Test func `all perpetuals flatten every perp DEX's meta in order`() async throws {
            let transport = FakeTransport(json: "[" + Self.btcMeta + "," + Self.xyzMeta + "]")
            let perpetuals = try await Self.market(transport).allPerpetuals()
            #expect(perpetuals.map(\.coin) == ["BTC", "xyz:XYZ100"])
            #expect(await transport.bodies == [#"{"type":"allPerpMetas"}"#])
        }

        @Test func `perp DEXs leave out the first perp DEX's null`() async throws {
            let transport = FakeTransport(
                json: #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888","oracleUpdater":null,"feeRecipient":null,"assetToStreamingOiCap":[["xyz:XYZ100","25000000.0"]]}]"#
            )
            let dexes = try await Self.market(transport).perpDexs()
            #expect(dexes.map(\.dex) == [.named("xyz")])
            #expect(dexes.first?.fundingMultipliers.isEmpty == true)
            #expect(await transport.bodies == [#"{"type":"perpDexs"}"#])
        }

        // MARK: Prices and trades

        @Test func `mids read the perp DEX's mids as decimals`() async throws {
            let transport = FakeTransport(json: #"{"xyz:XYZ100":"26264.0","xyz:TSLA":"0.000018"}"#)
            let mids = try await Self.market(transport).mids(dex: .named("xyz"))
            #expect(mids == ["xyz:XYZ100": Decimal(string: "26264")!, "xyz:TSLA": Decimal(string: "0.000018")!])
            #expect(await transport.bodies == [#"{"type":"allMids","dex":"xyz"}"#])
        }

        @Test func `an order book checks the coin once, then sends grouping only when it is set`() async throws {
            let book = #"{"coin":"BTC","time":1795518755141,"levels":[[{"px":"59660.0","sz":"1.5","n":3}],[]]}"#
            let transport = FakeTransport(responses: [.json(Self.btcMeta), .json(book), .json(book), .json(book)])
            let market = Self.market(transport)
            let full = try await market.orderBook("BTC")
            _ = try await market.orderBook("BTC", precision: .fiveSignificantFigures(mantissa: .two))
            _ = try await market.orderBook("BTC", precision: .significantFigures(.three))
            #expect(full.bids.map(\.price) == [Decimal(59660)])
            #expect(full.asks.isEmpty)
            #expect(await transport.bodies == [
                #"{"type":"meta","dex":""}"#,
                #"{"type":"l2Book","coin":"BTC"}"#,
                #"{"type":"l2Book","coin":"BTC","nSigFigs":5,"mantissa":2}"#,
                #"{"type":"l2Book","coin":"BTC","nSigFigs":3}"#,
            ])
        }

        @Test func `candles send the coin, interval and times in milliseconds inside req`() async throws {
            let transport = FakeTransport(responses: [.json(Self.perpDexs), .json(Self.xyzMeta), .json("[]")])
            let start = Date(timeIntervalSince1970: 1_795_496_400)
            let end = Date(timeIntervalSince1970: 1_795_518_752.9009)
            let candles = try await Self.market(transport)
                .candles("xyz:XYZ100", interval: .fifteenMinutes, from: start, to: end)
            #expect(candles.isEmpty)
            #expect(await transport.bodies.last
                == #"{"type":"candleSnapshot","req":{"coin":"xyz:XYZ100","interval":"15m","startTime":1795496400000,"endTime":1795518752900}}"#
            )
        }

        @Test func `recent trades send the coin`() async throws {
            let transport = FakeTransport(responses: [.json(Self.ethMeta), .json("[]")])
            _ = try await Self.market(transport).recentTrades("ETH")
            #expect(await transport.bodies.last == #"{"type":"recentTrades","coin":"ETH"}"#)
        }

        @Test func `a perpetual the perp DEX doesn't list throws unknown coin before the read is sent`() async {
            let transport = FakeTransport(json: Self.btcMeta)
            let market = Self.market(transport)
            for read in Self.coinReads(market, "NOPE") {
                await #expect {
                    try await read()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .unknownCoin
                }
            }
            #expect(await transport.bodies == [#"{"type":"meta","dex":""}"#])
        }

        @Test(arguments: ["@107", "PURR/USDC", "#10"] as [Hyperliquid.Coin])
        func `a spot or outcome coin throws unsupported market without a request`(coin: Hyperliquid.Coin) async {
            let transport = FakeTransport()
            for read in Self.coinReads(Self.market(transport), coin) {
                await #expect {
                    try await read()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
                }
            }
            #expect(await transport.requests.isEmpty)
        }

        /// Every market read that takes one coin.
        private static func coinReads(_ market: MarketRequests, _ coin: Hyperliquid.Coin)
            -> [@Sendable () async throws -> Void]
        {
            [
                { _ = try await market.orderBook(coin) },
                { _ = try await market.recentTrades(coin) },
                { _ = try await market.candles(coin, interval: .oneHour, from: .now, to: .now) },
                { _ = try await market.fundingHistory(coin, from: .now) },
            ]
        }

        @Test func `a coin on a perp DEX Hyperliquid doesn't list throws unknown coin before the read is sent`()
            async
        {
            let transport = FakeTransport(json: Self.perpDexs)
            await #expect {
                _ = try await Self.market(transport).recentTrades("foo:BTC")
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unknownCoin
            }
            #expect(await transport.bodies == [#"{"type":"perpDexs"}"#])
        }

        // MARK: Funding and limits

        @Test func `funding history leaves out the end time when there is none`() async throws {
            let transport = FakeTransport(responses: [.json(Self.btcMeta), .json("[]"), .json("[]")])
            let market = Self.market(transport)
            let start = Date(timeIntervalSince1970: 1_795_500_000)
            _ = try await market.fundingHistory("BTC", from: start)
            _ = try await market.fundingHistory("BTC", from: start, to: start.addingTimeInterval(3600))
            #expect(await transport.bodies.dropFirst() == [
                #"{"type":"fundingHistory","coin":"BTC","startTime":1795500000000}"#,
                #"{"type":"fundingHistory","coin":"BTC","startTime":1795500000000,"endTime":1795503600000}"#,
            ])
        }

        @Test func `perpetuals at their open interest cap send the perp DEX`() async throws {
            let transport = FakeTransport(json: #"["CANTO","FTM"]"#)
            let coins = try await Self.market(transport).openInterestCapped()
            #expect(coins == ["CANTO", "FTM"])
            #expect(await transport.bodies == [#"{"type":"perpsAtOpenInterestCap","dex":""}"#])
        }

        @Test func `predicted fundings leave out venues without a prediction`() async throws {
            let transport = FakeTransport(
                json: #"[["BTC",[["BinPerp",{"fundingRate":"0.0001","nextFundingTime":1795521600000,"fundingIntervalHours":4}],["HlPerp",null]]]]"#
            )
            let fundings = try await Self.market(transport).predictedFundings()
            #expect(fundings == [
                .init(coin: "BTC", venues: [
                    .init(exchange: .binance, rate: Decimal(string: "0.0001")!, nextFundingTime: Date(timeIntervalSince1970: 1_795_521_600))
                ])
            ])
            #expect(await transport.bodies == [#"{"type":"predictedFundings"}"#])
        }

        @Test func `the first perp DEX has no limits, without a request`() async throws {
            let transport = FakeTransport()
            #expect(try await Self.market(transport).perpDexLimits(dex: .first) == nil)
            #expect(await transport.requests.isEmpty)
        }

        @Test func `perp DEX limits are nil when Hyperliquid answers null`() async throws {
            let transport = FakeTransport(json: "null")
            #expect(try await Self.market(transport).perpDexLimits(dex: .named("xyz")) == nil)
        }

        @Test func `perp DEX limits and status send the perp DEX`() async throws {
            let limits = #"{"totalOiCap":"10000000.0","oiSzCapPerPerp":"10000000000.0","maxTransferNtl":"100000000.0","coinToOiCap":[["xyz:XYZ100","100000.0"]]}"#
            let transport = FakeTransport(responses: [.json(limits), .json(#"{"totalNetDeposit":"4103492112.4478230476"}"#)])
            let market = Self.market(transport)
            let dexLimits = try await market.perpDexLimits(dex: .named("xyz"))
            #expect(dexLimits?.openInterestCaps == ["xyz:XYZ100": Decimal(100_000)])
            #expect(try await market.perpDexStatus(dex: .named("xyz")).totalNetDeposit == Decimal(string: "4103492112.4478230476"))
            #expect(await transport.bodies == [
                #"{"type":"perpDexLimits","dex":"xyz"}"#, #"{"type":"perpDexStatus","dex":"xyz"}"#,
            ])
        }

        @Test func `a null answer to a read whose result isn't optional throws an unexpected response`() async {
            let transport = FakeTransport(json: "null")
            await #expect {
                _ = try await Self.market(transport).mids(dex: .named("nope"))
            } throws: { error in
                let error = error as? HyperliquidError
                return error?.kind == .unexpectedResponse && error?.httpStatus == 200
            }
        }

        @Test(arguments: [
            (Hyperliquid.OrderBook.Precision.full, #"{"type":"l2Book","coin":"BTC"}"#),
            (.significantFigures(.two), #"{"type":"l2Book","coin":"BTC","nSigFigs":2}"#),
            (.significantFigures(.four), #"{"type":"l2Book","coin":"BTC","nSigFigs":4}"#),
            (.significantFigures(.five), #"{"type":"l2Book","coin":"BTC","nSigFigs":5}"#),
            (.fiveSignificantFigures(mantissa: .one), #"{"type":"l2Book","coin":"BTC","nSigFigs":5,"mantissa":1}"#),
            (.fiveSignificantFigures(mantissa: .two), #"{"type":"l2Book","coin":"BTC","nSigFigs":5,"mantissa":2}"#),
            (.fiveSignificantFigures(mantissa: .five), #"{"type":"l2Book","coin":"BTC","nSigFigs":5,"mantissa":5}"#),
        ])
        func `each order book precision writes its parameters`(precision: Hyperliquid.OrderBook.Precision, body: String) {
            #expect(InfoRequest.l2Book("BTC", precision: precision).body.json == body)
        }

        // MARK: Exchange

        @Test func `exchange status reads the server time`() async throws {
            let transport = FakeTransport(json: #"{"specialStatuses":null,"time":1795507634079}"#)
            let status = try await Self.market(transport).exchangeStatus()
            #expect(status.time == Date(timeIntervalSince1970: 1_795_507_634.079))
            #expect(await transport.bodies == [#"{"type":"exchangeStatus"}"#])
        }

        private static func market(_ transport: FakeTransport) -> MarketRequests {
            MarketRequests(info: .test(transport), directory: AssetDirectory(info: .test(transport)))
        }
    }
}
