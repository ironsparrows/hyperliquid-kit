import Foundation
import HyperliquidKit
import Testing

extension HyperliquidKitTests {
    // The suites that trade on mainnet, run one at a time so that one's leverage change or close
    // never meets another's BTC position or order.
    @Suite("Live trading", .serialized)
    struct LiveTradingTests {
        /// A BTC size worth about `dollars` at `price`, or at the mid price, rounded up to BTC's size
        /// decimals.
        static func btcSize(worth dollars: Decimal, at price: Decimal? = nil, on client: Hyperliquid.Client)
            async throws -> Decimal
        {
            let mid = try #require(try await client.market.mids()["BTC"])
            let sizeDecimals = try #require(try await client.market.perpetuals().first { $0.coin == "BTC" }).sizeDecimals
            var exact = dollars / (price ?? mid)
            var size = Decimal()
            NSDecimalRound(&size, &exact, sizeDecimals, .up)
            return size
        }
    }
}
