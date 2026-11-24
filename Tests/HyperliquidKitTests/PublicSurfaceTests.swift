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
                Hyperliquid.PrivateKeySigner.self, (any Hyperliquid.API).self, (any Hyperliquid.MarketAPI).self,
                Hyperliquid.Client.self, Hyperliquid.Client.Configuration.self, Hyperliquid.Perpetual.self,
                Hyperliquid.MarginTable.self, Hyperliquid.MarginTable.Tier.self, Hyperliquid.AssetContext.self, Hyperliquid.PerpetualContext.self,
                Hyperliquid.PerpDex.Details.self,
                Hyperliquid.OrderRequest.self, Hyperliquid.TriggerExecution.self, Hyperliquid.Grouping.self,
                Hyperliquid.PlacementResult.self, Hyperliquid.PlacementResult.Status.self, Hyperliquid.CancelResult.self,
                Hyperliquid.OrderReference.self, Hyperliquid.ClientOrderReference.self, Hyperliquid.OrderChange.self, Hyperliquid.OrderBook.self, Hyperliquid.OrderBook.Level.self, Hyperliquid.OrderBook.Precision.self,
                Hyperliquid.OrderBook.Precision.SignificantFigures.self, Hyperliquid.OrderBook.Precision.Mantissa.self,
                Hyperliquid.Candle.self, Hyperliquid.Candle.Interval.self, Hyperliquid.Trade.self,
                Hyperliquid.TradeID.self, Hyperliquid.FundingRate.self, Hyperliquid.PredictedFunding.self,
                Hyperliquid.PredictedFunding.Venue.self, Hyperliquid.PredictedFunding.Exchange.self,
                Hyperliquid.PerpDex.Limits.self, Hyperliquid.PerpDex.Status.self, Hyperliquid.ExchangeStatus.self,
                (any Hyperliquid.AccountAPI).self, (any Hyperliquid.PositionAPI).self, Hyperliquid.Leverage.self,
                Hyperliquid.PerpetualState.self, Hyperliquid.PerpetualState.MarginSummary.self,
                Hyperliquid.PerpetualState.Position.self, Hyperliquid.PerpetualState.CumulativeFunding.self,
                Hyperliquid.Balance.self, Hyperliquid.TradingLimits.self, Hyperliquid.Fees.self,
                Hyperliquid.Fees.DailyVolume.self, Hyperliquid.Fees.Schedule.self, Hyperliquid.Fees.VolumeTier.self,
                Hyperliquid.Fees.MarketMakerTier.self, Hyperliquid.Fees.StakingDiscountTier.self,
                Hyperliquid.RateLimit.self, Hyperliquid.AccountRole.self, Hyperliquid.AccountRole.Kind.self,
                Hyperliquid.SubAccount.self, Hyperliquid.Portfolio.self, Hyperliquid.Portfolio.Window.self,
                Hyperliquid.Portfolio.History.self, Hyperliquid.Portfolio.Sample.self, Hyperliquid.APIWallet.self,
                Hyperliquid.FundingPayment.self, Hyperliquid.LedgerUpdate.self, Hyperliquid.LedgerUpdate.Change.self,
                Hyperliquid.Coin.Kind.self, (any Hyperliquid.OrderAPI).self, (any Hyperliquid.TwapAPI).self,
                Hyperliquid.OrderIdentifier.self, Hyperliquid.Order.self, Hyperliquid.Order.Details.self,
                Hyperliquid.Order.Kind.self, Hyperliquid.HistoricalOrder.self, Hyperliquid.Fill.self,
                Hyperliquid.Fill.Direction.self, Hyperliquid.Fill.Liquidation.self, Hyperliquid.Fill.Liquidation.Method.self,
                Hyperliquid.Twap.self, Hyperliquid.Twap.Status.self, Hyperliquid.TwapSliceFill.self,
                Hyperliquid.TwapHistoryEntry.self,
                Hyperliquid.TwapRequest.self, Hyperliquid.TwapPlacementResult.self,
                (any Hyperliquid.StreamAPI).self, Hyperliquid.BestBidOffer.self, Hyperliquid.Batch<Hyperliquid.Fill>.self,
                Hyperliquid.UserEvent.self, Hyperliquid.UserEvent.Liquidation.self, Hyperliquid.LiquidationID.self,
                Hyperliquid.MarketPrices.self,
            ]
            _ = types
        }
    }
}
