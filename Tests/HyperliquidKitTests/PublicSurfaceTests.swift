import HyperliquidKit
import Testing

// Only `import HyperliquidKit`: the check is that this compiles. It stops compiling if a public type
// stops reaching apps through the umbrella module.
extension HyperliquidKitTests {
    @Suite("Public surface")
    struct PublicSurfaceTests {
        @Test func `every public type is reachable through import HyperliquidKit`() {
            let types: [Any.Type] = [
                Hyperliquid.self, HyperliquidError.self, HyperliquidError.Kind.self,
                Hyperliquid.ClientError.self, Hyperliquid.ClientError.Reason.self,
                Hyperliquid.Address.self, Hyperliquid.Coin.self, Hyperliquid.PerpDex.self,
                Hyperliquid.OrderID.self, Hyperliquid.ClientOrderID.self, Hyperliquid.TwapID.self,
                Hyperliquid.TransactionHash.self, Hyperliquid.Network.self, Hyperliquid.Slippage.self,
                Hyperliquid.Side.self, Hyperliquid.TimeInForce.self, Hyperliquid.TriggerKind.self,
                Hyperliquid.OrderStatus.self, Hyperliquid.MarginMode.self, Hyperliquid.AccountMode.self,
                (any Hyperliquid.Signer).self, Hyperliquid.SigningRequest.self, Hyperliquid.Signature.self,
                Hyperliquid.PrivateKeySigner.self,
            ]
            _ = types
        }
    }
}
