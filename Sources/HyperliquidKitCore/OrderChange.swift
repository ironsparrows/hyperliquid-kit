extension Hyperliquid {
    /// An order to modify and its new version.
    public struct OrderChange: Hashable, Sendable {
        public let order: OrderIdentifier
        public let newOrder: OrderRequest

        public init(_ order: OrderIdentifier, to newOrder: OrderRequest) {
            self.order = order
            self.newOrder = newOrder
        }
    }
}
