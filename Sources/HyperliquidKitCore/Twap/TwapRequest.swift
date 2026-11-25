public import Foundation

extension Hyperliquid {
    /// A TWAP order to place: a size bought or sold in slices over a whole number of minutes.
    ///
    /// Hyperliquid accepts a duration from 5 minutes to 7 days and a total value of at least $100, and
    /// sends a slice at most every 30 seconds.
    public struct TwapRequest: Hashable, Sendable {
        public let side: Side
        public let coin: Coin
        /// The whole size, in the base coin.
        public let size: Decimal
        /// How long the TWAP runs; it must be a whole number of minutes.
        public let duration: Duration
        public let reduceOnly: Bool
        /// Whether the slices are randomized.
        public let randomize: Bool

        public init(
            _ side: Side, _ coin: Coin, size: Decimal, duration: Duration, reduceOnly: Bool = false,
            randomize: Bool = false
        ) {
            self.side = side
            self.coin = coin
            self.size = size
            self.duration = duration
            self.reduceOnly = reduceOnly
            self.randomize = randomize
        }
    }
}
