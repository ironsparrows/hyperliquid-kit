extension Hyperliquid {
    /// Every Hyperliquid capability the SDK offers, grouped by domain.
    ///
    /// `Hyperliquid.Client` conforms. Depend on this protocol, or on one domain's protocol, to substitute a mock.
    public protocol API: Sendable {
        var market: any MarketAPI { get }
        var account: any AccountAPI { get }
        var position: any PositionAPI { get }
        var order: any OrderAPI { get }
        var twap: any TwapAPI { get }
        var stream: any StreamAPI { get }
    }
}
