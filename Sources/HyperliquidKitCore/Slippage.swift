public import Foundation

extension Hyperliquid {
    /// How far from the mid price a market order may fill: a worst-price cap, not an expected cost.
    ///
    /// `.percent(5)` and `.fraction(0.05)` are the same slippage.
    public struct Slippage: Hashable, Sendable {
        package let fraction: Decimal

        private init(fraction: Decimal) {
            self.fraction = fraction
        }

        public static func percent(_ percent: Decimal) -> Self {
            Self(fraction: percent / 100)
        }

        public static func fraction(_ fraction: Decimal) -> Self {
            Self(fraction: fraction)
        }
    }
}
