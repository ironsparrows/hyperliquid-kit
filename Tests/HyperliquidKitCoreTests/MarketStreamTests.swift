import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Market stream pushes")
    struct MarketStreamTests {
        /// The `data` of a recorded push `{"channel": …, "data": …}`, as JSON.
        private func payload(_ name: String) throws -> Data {
            let push = try #require(try JSONSerialization.jsonObject(with: Fixture.data(name)) as? [String: Any])
            return try JSONSerialization.data(withJSONObject: try #require(push["data"]))
        }

        @Test func `a recorded book push decodes, on full and grouped precision`() throws {
            let book = try JSONDecoder().decode(Hyperliquid.OrderBook.self, from: payload("ws_l2Book"))
            #expect(book.coin == "BTC")
            #expect(book.time == Date(timeIntervalSince1970: 1_795_530_169.945))
            #expect(!book.bids.isEmpty && !book.asks.isEmpty)
            let grouped = try JSONDecoder().decode(Hyperliquid.OrderBook.self, from: payload("ws_l2Book_ETH"))
            #expect(grouped.coin == "ETH")
        }

        @Test func `a recorded best bid and offer push decodes`() throws {
            let best = try JSONDecoder().decode(Hyperliquid.BestBidOffer.self, from: payload("ws_bbo"))
            #expect(best.coin == "BTC")
            #expect(best.bid == .init(price: Decimal(60326), size: Decimal(string: "2.03339")!, orderCount: 21))
            #expect(best.ask?.price == Decimal(60327))
        }

        @Test func `a best bid and offer with an empty side decodes it as nil`() throws {
            let best = try JSONDecoder().decode(
                Hyperliquid.BestBidOffer.self,
                from: Data(#"{"coin":"BTC","time":1795530170160,"bbo":[null,{"px":"60327.0","sz":"1","n":1}]}"#.utf8)
            )
            #expect(best.bid == nil)
            #expect(best.ask?.orderCount == 1)
        }

        @Test func `a recorded trades push decodes every trade`() throws {
            let trades = try JSONDecoder().decode([Hyperliquid.Trade].self, from: payload("ws_trades"))
            #expect(trades.count > 1)
            #expect(trades.allSatisfy { $0.coin == "BTC" })
        }

        @Test func `a recorded candle push decodes`() throws {
            let candle = try JSONDecoder().decode(Hyperliquid.Candle.self, from: payload("ws_candle"))
            #expect(candle.coin == "BTC")
            #expect(candle.interval == .oneMinute)
            #expect(candle.openTime == Date(timeIntervalSince1970: 1_795_530_120))
            #expect(candle.tradeCount == 117)
        }

        @Test func `recorded asset context pushes decode on the first and a builder-deployed perp DEX`() throws {
            struct Push: Decodable {
                let coin: Hyperliquid.Coin
                let ctx: Hyperliquid.AssetContext
            }
            let btc = try JSONDecoder().decode(Push.self, from: payload("ws_activeAssetCtx"))
            #expect(btc.coin == "BTC")
            #expect(btc.ctx.funding == Decimal(string: "-0.0000015398"))
            let xyz = try JSONDecoder().decode(Push.self, from: payload("ws_activeAssetCtx_xyz"))
            #expect(xyz.coin.dex == .named("xyz"))
        }
    }
}
