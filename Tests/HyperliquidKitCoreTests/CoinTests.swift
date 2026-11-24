import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Coin and perp DEX")
    struct CoinTests {
        @Test(arguments: [
            (Hyperliquid.Coin("BTC"), Hyperliquid.PerpDex.first),
            ("kPEPE", .first),
            ("xyz:XYZ100", .named("xyz")),
            ("flx:TSLA", .named("flx")),
        ])
        func `a coin's perp DEX is the name before the colon`(coin: Hyperliquid.Coin, dex: Hyperliquid.PerpDex) {
            #expect(coin.dex == dex)
        }

        @Test func `the first perp DEX has an empty name`() {
            #expect(Hyperliquid.PerpDex.first.name == "")
            #expect(Hyperliquid.PerpDex.named("") == .first)
        }

        @Test func `a coin and a perp DEX encode as their names`() throws {
            let coins: [Hyperliquid.Coin] = ["BTC", "xyz:XYZ100"]
            let dexes: [Hyperliquid.PerpDex] = [.first, .named("xyz")]
            #expect(try roundTrip(coins) == #"["BTC","xyz:XYZ100"]"#)
            #expect(try roundTrip(dexes) == #"["","xyz"]"#)
        }

        private func roundTrip<Value: Codable & Equatable>(_ values: [Value]) throws -> String {
            let data = try JSONEncoder().encode(values)
            #expect(try JSONDecoder().decode([Value].self, from: data) == values)
            return String(decoding: data, as: UTF8.self)
        }
    }
}
