public import Foundation

extension Hyperliquid {
    /// A market's mark and mid prices.
    public struct MarketPrices: Hashable, Sendable {
        /// The mark price, once Hyperliquid has sent one.
        public let markPrice: Decimal?
        /// The middle of the best bid and ask, or `nil` when the book has no mid or Hyperliquid hasn't
        /// sent one.
        public let midPrice: Decimal?

        public init(markPrice: Decimal?, midPrice: Decimal?) {
            self.markPrice = markPrice
            self.midPrice = midPrice
        }
    }
}
