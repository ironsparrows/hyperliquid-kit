import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Orders and fills")
    struct OrderHistoryTests {
        private let decoder = JSONDecoder()

        private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
            try decoder.decode(type, from: Data(json.utf8))
        }

        // MARK: Orders

        @Test func `a pending order decodes without details`() throws {
            let orders = try decode(
                [Hyperliquid.Order].self,
                #"[{"coin":"BTC","limitPx":"29792.0","oid":91490942,"side":"A","sz":"0.0","timestamp":1681247412573}]"#
            )
            #expect(orders == [.init(
                coin: "BTC", side: .sell, limitPrice: Decimal(29792), size: 0, id: .init(rawValue: 91_490_942),
                time: Date(timeIntervalSince1970: 1_681_247_412.573)
            )])
        }

        @Test func `a detailed pending order decodes its trigger, with no time in force or children`() throws {
            let order = try decode(
                Hyperliquid.Order.self,
                #"{"children":[],"coin":"INJ","isPositionTpsl":false,"isTrigger":true,"limitPx":"9.2037","oid":3184595907,"orderType":"Take Profit Market","origSz":"12.5","reduceOnly":true,"side":"A","sz":"12.5","tif":null,"timestamp":1700126022555,"triggerCondition":"Price above 10.004","triggerPx":"10.004"}"#
            )
            let details = try #require(order.details)
            #expect(details.kind == .takeProfitMarket)
            #expect(details.isTrigger)
            #expect(details.reduceOnly)
            #expect(details.triggerPrice == Decimal(string: "10.004"))
            #expect(details.triggerCondition == "Price above 10.004")
            #expect(details.timeInForce == nil)
            #expect(details.originalSize == Decimal(string: "12.5"))
            let documented = try decode(
                Hyperliquid.Order.self,
                #"{"coin":"BTC","isPositionTpsl":false,"isTrigger":false,"limitPx":"29792.0","oid":91490942,"orderType":"Limit","origSz":"5.0","reduceOnly":false,"side":"A","sz":"5.0","timestamp":1681247412573,"triggerCondition":"N/A","triggerPx":"0.0"}"#
            )
            #expect(documented.details?.kind == .limit)
            #expect(documented.details?.children.isEmpty == true)
        }

        @Test func `a historical order decodes with its status, client ID and children`() throws {
            let child = #"{"coin":"ETH","side":"B","limitPx":"2500.0","sz":"0.0","oid":2,"timestamp":1724361546645,"triggerCondition":"Price above 2500","isTrigger":true,"triggerPx":"2500.0","children":[],"isPositionTpsl":false,"reduceOnly":true,"orderType":"Stop Market","origSz":"0.0076","tif":null,"cloid":null}"#
            let orders = try decode(
                [Hyperliquid.HistoricalOrder].self,
                #"[{"order":{"coin":"ETH","side":"A","limitPx":"2412.7","sz":"0.0","oid":1,"timestamp":1724361546645,"triggerCondition":"N/A","isTrigger":false,"triggerPx":"0.0","children":["# + child
                    + #"],"isPositionTpsl":false,"reduceOnly":true,"orderType":"Market","origSz":"0.0076","tif":"FrontendMarket","cloid":"0x00000000000000000000000000000001"},"status":"filled","statusTimestamp":1724361546645}]"#
            )
            let historical = try #require(orders.first)
            #expect(historical.status == .filled)
            #expect(historical.statusTime == Date(timeIntervalSince1970: 1_724_361_546.645))
            #expect(historical.order.clientID?.description == "0x00000000000000000000000000000001")
            #expect(historical.order.details?.timeInForce == .frontendMarket)
            #expect(historical.order.details?.children.first?.details?.kind == .stopMarket)
        }

        @Test func `an order status answer decodes the order, or nothing for an unknown order`() throws {
            let known = try decode(
                OrderStatusResponse.self,
                #"{"status":"order","order":{"order":{"coin":"ETH","side":"A","limitPx":"2412.7","sz":"0.0","oid":1,"timestamp":1724361546645,"triggerCondition":"N/A","isTrigger":false,"triggerPx":"0.0","children":[],"isPositionTpsl":false,"reduceOnly":true,"orderType":"Market","origSz":"0.0076","tif":"FrontendMarket","cloid":null},"status":"marginCanceled","statusTimestamp":1724361546645}}"#
            )
            #expect(known.order?.status == .marginCanceled)
            #expect(known.order?.order.clientID == nil)
            #expect(try decode(OrderStatusResponse.self, #"{"status":"unknownOid"}"#).order == nil)
            #expect(throws: DecodingError.self) { try decode(OrderStatusResponse.self, #"{"status":"other"}"#) }
        }

        // MARK: Fills

        @Test func `recorded fills decode`() throws {
            let fills = try decoder.decode([Hyperliquid.Fill].self, from: Fixture.data("userFillsByTime"))
            #expect(fills.count == 8)
            let first = try #require(fills.first)
            #expect(first.coin == "SHIA")
            #expect(first.direction == .settlement)
            #expect(first.price == Decimal(string: "0.000617"))
            #expect(first.tradeID == .init(rawValue: 1_042_094_259_263_655))
            #expect(first.feeToken == "USDC")
            #expect(first.twapID == nil)
            #expect(!first.isTaker)
        }

        @Test func `documented perpetual, HIP-3 and spot fills decode, with their kinds`() throws {
            let fills = try decode([Hyperliquid.Fill].self, Self.documentedFills)
            #expect(fills.map(\.coin.kind) == [.perpetual, .perpetual, .spot])
            #expect(fills[0].builderFee == Decimal(string: "0.01"))
            #expect(fills[0].direction == .openLong)
            #expect(fills[1].builderFee == nil)
            #expect(fills[1].coin.dex == .named("xyz"))
            #expect(fills[2].direction == .sell)
            #expect(fills[2].isTaker)
            #expect(fills[2].closedPnL == Decimal(string: "8722.988077"))
        }

        @Test func `a fill without a trade ID or fee token decodes`() throws {
            let fill = try decode(
                Hyperliquid.Fill.self,
                #"{"closedPnl":"-0.25686","coin":"SUI","crossed":true,"dir":"Close Short","fee":"0.0","hash":"0x0000000000000000000000000000000000000000000000000000000000000001","oid":189324432,"px":"1.3189","side":"B","startPosition":"-4623.5","sz":"142.7","time":1683245884863}"#
            )
            #expect(fill.tradeID == nil)
            #expect(fill.feeToken == nil)
            #expect(fill.direction == .closeShort)
        }

        @Test func `a liquidation fill decodes its liquidation`() throws {
            let fill = try decode(
                Hyperliquid.Fill.self,
                #"{"coin":"ETH","px":"2000.0","sz":"1.0","side":"A","time":1681222254710,"startPosition":"1.0","dir":"Close Long","closedPnl":"-10.0","hash":"0x0000000000000000000000000000000000000000000000000000000000000001","oid":1,"crossed":true,"fee":"0.9","tid":1,"feeToken":"USDC","liquidation":{"liquidatedUser":"0x00000000000000000000000000000000000000a1","markPx":"2001.0","method":"market"}}"#
            )
            #expect(fill.liquidation == .init(
                liquidatedUser: "0x00000000000000000000000000000000000000a1", markPrice: Decimal(2001), method: .market
            ))
        }

        // MARK: TWAP

        @Test func `a TWAP slice fill decodes with its TWAP ID and zero hash`() throws {
            let fills = try decode(
                [Hyperliquid.TwapSliceFill].self,
                #"[{"fill":{"closedPnl":"0.0","coin":"AVAX","crossed":true,"dir":"Open Long","hash":"0x0000000000000000000000000000000000000000000000000000000000000000","oid":90542681,"px":"18.435","side":"B","startPosition":"26.86","sz":"93.53","time":1681222254710,"fee":"0.01","feeToken":"USDC","tid":118906512037719},"twapId":3156}]"#
            )
            #expect(fills.first?.twapID == .init(rawValue: 3156))
            #expect(fills.first?.fill.size == Decimal(string: "93.53"))
        }

        @Test func `recorded TWAP history decodes, its time in seconds and the start in milliseconds`() throws {
            let entries = try decoder.decode([Hyperliquid.TwapHistoryEntry].self, from: Fixture.data("twapHistory"))
            #expect(entries.count == 86)
            let first = try #require(entries.first)
            #expect(first.twapID == .init(rawValue: 2_722_906))
            #expect(first.status == .terminated)
            #expect(first.time == Date(timeIntervalSince1970: 1_794_950_203))
            #expect(first.twap.startTime == Date(timeIntervalSince1970: 1_794_949_316.725))
            #expect(first.twap.coin == "io:NVDA")
            #expect(first.twap.duration == .seconds(17 * 60))
            #expect(entries.contains { $0.status == .error && $0.statusDescription != nil })
            #expect(entries.allSatisfy { abs($0.time.timeIntervalSince($0.twap.startTime)) < 86_400 })
        }

        private static let documentedFills = #"[{"closedPnl":"0.0","coin":"AVAX","crossed":false,"dir":"Open Long","hash":"0x0000000000000000000000000000000000000000000000000000000000000001","oid":90542681,"px":"18.435","side":"B","startPosition":"26.86","sz":"93.53","time":1681222254710,"fee":"0.01","feeToken":"USDC","builderFee":"0.01","tid":118906512037719},{"coin":"xyz:XYZ100","px":"25372.0","sz":"0.0353","side":"B","time":1767651180109,"startPosition":"0.7045","dir":"Open Long","closedPnl":"0.0","hash":"0x0000000000000000000000000000000000000000000000000000000000000002","oid":287286372177,"crossed":false,"fee":"0.026868","tid":164087028129848,"feeToken":"USDC"},{"coin":"@107","px":"18.62041381","sz":"43.84","side":"A","time":1735969713869,"startPosition":"10659.65434798","dir":"Sell","closedPnl":"8722.988077","hash":"0x0000000000000000000000000000000000000000000000000000000000000003","oid":59071663721,"crossed":true,"fee":"0.304521","tid":907359904431134,"feeToken":"USDC"}]"#
    }
}
