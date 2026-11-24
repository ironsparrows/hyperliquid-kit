/// The namespace for Hyperliquid perpetuals and the account behind them.
///
/// Every API type except ``HyperliquidError`` is nested here, so names like `Order`, `Signer` or
/// `Address` can't collide with an app's own types, another exchange SDK's or a dependency's.
public enum Hyperliquid {}

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
