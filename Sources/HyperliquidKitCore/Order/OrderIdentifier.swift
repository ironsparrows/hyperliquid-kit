extension Hyperliquid {
    /// An order named by Hyperliquid's ID or by the app's client order ID.
    public enum OrderIdentifier: Hashable, Sendable {
        case id(OrderID)
        case clientID(ClientOrderID)
    }
}
