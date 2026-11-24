import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Market data")
    struct MarketDataTests {
        private let decoder = JSONDecoder()

        @Test func `mids decode keyed by coin, spot and HIP-3 coins included`() throws {
            let mids = try decoder.decode([Hyperliquid.Coin: WireDecimal].self, from: Fixture.data("allMids"))
            #expect(mids.count == 1430)
            #expect(mids["BTC"]?.value == Decimal(59664))
            #expect(mids["@107"]?.value == Decimal(string: "62.3375"))
            let xyz = try decoder.decode([Hyperliquid.Coin: WireDecimal].self, from: Fixture.data("allMids_xyz"))
            #expect(xyz["xyz:XYZ100"]?.value == Decimal(26264))
        }

        @Test func `a dictionary keyed by coin round-trips as a JSON object`() throws {
            let values: [Hyperliquid.Coin: Int] = ["BTC": 1, "xyz:XYZ100": 2]
            let data = try JSONEncoder().encode(values)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Int])
            #expect(object == ["BTC": 1, "xyz:XYZ100": 2])
            #expect(try decoder.decode([Hyperliquid.Coin: Int].self, from: data) == values)
        }

        @Test func `an order book decodes bids then asks, 20 levels each`() throws {
            let book = try decoder.decode(Hyperliquid.OrderBook.self, from: Fixture.data("l2Book"))
            #expect(book.coin == "BTC")
            #expect(book.time == Date(timeIntervalSince1970: 1_795_518_755.141))
            #expect(book.bids.count == 20)
            #expect(book.asks.count == 20)
            #expect(book.bids.first == .init(price: Decimal(string: "59660.0")!, size: Decimal(string: "13.39124")!, orderCount: 32))
            #expect(book.asks.first == .init(price: Decimal(string: "59661.0")!, size: Decimal(string: "0.6305")!, orderCount: 4))
        }

        @Test func `a level without an order count decodes with none`() throws {
            let level = try decoder.decode(Hyperliquid.OrderBook.Level.self, from: Data(#"{"px":"1.5","sz":"2"}"#.utf8))
            #expect(level == .init(price: Decimal(string: "1.5")!, size: 2, orderCount: nil))
        }

        @Test func `candles decode with their interval and times`() throws {
            let candles = try decoder.decode([Hyperliquid.Candle].self, from: Fixture.data("candleSnapshot"))
            #expect(candles.count == 7)
            let first = try #require(candles.first)
            #expect(first.coin == "BTC")
            #expect(first.interval == .oneHour)
            #expect(first.openTime == Date(timeIntervalSince1970: 1_795_496_400))
            #expect(first.closeTime == Date(timeIntervalSince1970: 1_795_499_999.999))
            #expect(first.open == Decimal(string: "60354.0"))
            #expect(first.high == Decimal(string: "60745.0"))
            #expect(first.low == Decimal(string: "60287.0"))
            #expect(first.close == Decimal(string: "60599.0"))
            #expect(first.volume == Decimal(string: "1240.45373"))
            #expect(first.tradeCount == 11380)
        }

        @Test func `recent trades decode with their ID, buyer and seller`() throws {
            let trades = try decoder.decode([Hyperliquid.Trade].self, from: Fixture.data("recentTrades"))
            #expect(trades.count == 10)
            let first = try #require(trades.first)
            #expect(first.side == .buy)
            #expect(first.price == Decimal(string: "59661.0"))
            #expect(first.size == Decimal(string: "0.01275"))
            #expect(first.id == Hyperliquid.TradeID(rawValue: 1_106_373_003_298_555))
            #expect(first.hash.rawValue == "0x0000000000000000000000000000000000000000000000000000000000000065")
            #expect(first.buyer.description == "0x0000000000000000000000000000000000000001")
            #expect(first.seller.description == "0x0000000000000000000000000000000000000002")
        }

        @Test func `funding rates decode on the first perp DEX and a builder-deployed one`() throws {
            let rates = try decoder.decode([Hyperliquid.FundingRate].self, from: Fixture.data("fundingHistory"))
            #expect(rates.count == 5)
            #expect(rates.first == .init(
                coin: "BTC", rate: Decimal(string: "0.0000056633")!, premium: Decimal(string: "-0.0004546934")!,
                time: Date(timeIntervalSince1970: 1_795_503_600.022)
            ))
            let xyz = try decoder.decode([Hyperliquid.FundingRate].self, from: Fixture.data("fundingHistory_xyz"))
            #expect(xyz.allSatisfy { $0.coin.dex == .named("xyz") })
        }

        @Test func `perpetuals at their open interest cap decode as coins`() throws {
            let coins = try decoder.decode([Hyperliquid.Coin].self, from: Fixture.data("perpsAtOpenInterestCap"))
            #expect(coins.first == "CANTO")
            #expect(coins.count == 10)
        }

        @Test func `predicted fundings decode each venue's prediction and leave out the null ones`() throws {
            let fundings = try decoder.decode([Hyperliquid.PredictedFunding].self, from: Fixture.data("predictedFundings"))
            #expect(fundings.count == 235)
            #expect(fundings.flatMap(\.venues).count == 631)
            let first = try #require(fundings.first)
            #expect(first.coin == "0G")
            #expect(first.venues.map(\.exchange) == [.binance, .hyperliquid, .bybit])
            #expect(first.venues[1].rate == Decimal(string: "0.0000125"))
            #expect(first.venues[1].nextFundingTime == Date(timeIntervalSince1970: 1_795_518_000))
        }

        @Test func `a builder-deployed perp DEX's limits decode`() throws {
            let limits = try decoder.decode(Hyperliquid.PerpDex.Limits.self, from: Fixture.data("perpDexLimits_xyz"))
            #expect(limits.totalOpenInterestCap == Decimal(10_000_000_000))
            #expect(limits.openInterestSizeCapPerPerpetual == Decimal(20_000_000_000))
            #expect(limits.maxTransferNotional == Decimal(3_000_000_000))
            #expect(limits.openInterestCaps.count == 139)
            #expect(limits.openInterestCaps["xyz:AAOI"] == Decimal(25_000_000))
        }

        @Test func `a perp DEX's status and the exchange status decode`() throws {
            let status = try decoder.decode(Hyperliquid.PerpDex.Status.self, from: Fixture.data("perpDexStatus_xyz"))
            #expect(status.totalNetDeposit == Decimal(string: "1093777245.6014618874"))
            let exchange = try decoder.decode(Hyperliquid.ExchangeStatus.self, from: Fixture.data("exchangeStatus"))
            #expect(exchange.time == Date(timeIntervalSince1970: 1_795_518_752.9))
        }

        @Test(arguments: [
            (Hyperliquid.Candle.Interval.oneMinute, "1m"), (.threeMinutes, "3m"), (.fiveMinutes, "5m"),
            (.fifteenMinutes, "15m"), (.thirtyMinutes, "30m"), (.oneHour, "1h"), (.twoHours, "2h"),
            (.fourHours, "4h"), (.eightHours, "8h"), (.twelveHours, "12h"), (.oneDay, "1d"), (.threeDays, "3d"),
            (.oneWeek, "1w"), (.oneMonth, "1M"),
        ])
        func `each candle interval has Hyperliquid's spelling`(interval: Hyperliquid.Candle.Interval, raw: String) {
            #expect(interval.rawValue == raw)
        }
    }
}
