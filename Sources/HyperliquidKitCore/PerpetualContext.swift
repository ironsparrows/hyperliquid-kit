extension Hyperliquid {
    /// A perpetual with its market state, as ``MarketAPI/perpetualContexts(dex:)`` returns them.
    public struct PerpetualContext: Hashable, Sendable {
        public let perpetual: Perpetual
        public let context: AssetContext

        public init(perpetual: Perpetual, context: AssetContext) {
            self.perpetual = perpetual
            self.context = context
        }
    }
}
