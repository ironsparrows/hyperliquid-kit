# ``HyperliquidKit``

Trade Hyperliquid's perpetuals from Swift: market data, the account, orders and live streams.

## Overview

HyperliquidKit calls Hyperliquid's `/info` and `/exchange` endpoints and its WebSocket streams. One
``Hyperliquid/Client`` holds every capability, grouped by domain: `client.market`,
`client.account`, `client.position`, `client.order`, `client.twap` and `client.stream`. Each domain
is a protocol, so a test can replace one with a mock.

```swift
import HyperliquidKit

let client = Hyperliquid.Client()
let mids = try await client.market.mids()
```

Reads and streams need only an account's address, and market data not even that. Actions, such as
placing an order, are signed by the client's ``Hyperliquid/Signer``, usually an API wallet's key in
a ``Hyperliquid/PrivateKeySigner``; see <doc:APIWallets>.

Prices, sizes and amounts are `Decimal`, read exactly as Hyperliquid sends them; sizes are in the
coin traded. Every call that needs Hyperliquid's answer is `async`. It throws ``HyperliquidError``
when Hyperliquid refuses it or answers in a way the client can't use, and
``Hyperliquid/ClientError`` when the client couldn't complete it; besides those, canceling throws
`CancellationError`. A stream push the client can't read ends its stream with `DecodingError`.

The client covers perpetuals, on the first perp DEX and on builder-deployed ones. Spot markets
appear only where Hyperliquid mixes them into an account's results, mid prices or the prices
stream.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:APIWallets>
- ``Hyperliquid/Client``
- ``Hyperliquid/API``
- ``Hyperliquid/Address``
- ``Hyperliquid/Coin``
- ``Hyperliquid/PerpDex``
- ``Hyperliquid/Network``

### Signing

- ``Hyperliquid/Signer``
- ``Hyperliquid/PrivateKeySigner``
- ``Hyperliquid/SigningRequest``
- ``Hyperliquid/Signature``

### Market data

- ``Hyperliquid/MarketAPI``
- ``Hyperliquid/Perpetual``
- ``Hyperliquid/MarginTable``
- ``Hyperliquid/AssetContext``
- ``Hyperliquid/PerpetualContext``
- ``Hyperliquid/OrderBook``
- ``Hyperliquid/Trade``
- ``Hyperliquid/TradeID``
- ``Hyperliquid/Candle``
- ``Hyperliquid/FundingRate``
- ``Hyperliquid/PredictedFunding``
- ``Hyperliquid/ExchangeStatus``

### Account

- ``Hyperliquid/AccountAPI``
- ``Hyperliquid/PerpetualState``
- ``Hyperliquid/Balance``
- ``Hyperliquid/AccountMode``
- ``Hyperliquid/Fees``
- ``Hyperliquid/RateLimit``
- ``Hyperliquid/AccountRole``
- ``Hyperliquid/SubAccount``
- ``Hyperliquid/APIWallet``
- ``Hyperliquid/Portfolio``
- ``Hyperliquid/LedgerUpdate``
- ``Hyperliquid/TransactionHash``

### Positions, leverage and margin

- ``Hyperliquid/PositionAPI``
- ``Hyperliquid/Leverage``
- ``Hyperliquid/MarginMode``
- ``Hyperliquid/TradingLimits``
- ``Hyperliquid/FundingPayment``

### Orders and market orders

- ``Hyperliquid/OrderAPI``
- ``Hyperliquid/OrderRequest``
- ``Hyperliquid/Side``
- ``Hyperliquid/TimeInForce``
- ``Hyperliquid/TriggerKind``
- ``Hyperliquid/TriggerExecution``
- ``Hyperliquid/Slippage``
- ``Hyperliquid/Grouping``
- ``Hyperliquid/PlacementResult``
- ``Hyperliquid/OrderReference``
- ``Hyperliquid/ClientOrderReference``
- ``Hyperliquid/CancelResult``
- ``Hyperliquid/OrderChange``
- ``Hyperliquid/OrderIdentifier``
- ``Hyperliquid/OrderID``
- ``Hyperliquid/ClientOrderID``
- ``Hyperliquid/Order``
- ``Hyperliquid/HistoricalOrder``
- ``Hyperliquid/OrderStatus``
- ``Hyperliquid/Fill``

### TWAP orders

- ``Hyperliquid/TwapAPI``
- ``Hyperliquid/TwapRequest``
- ``Hyperliquid/TwapPlacementResult``
- ``Hyperliquid/TwapID``
- ``Hyperliquid/Twap``
- ``Hyperliquid/TwapSliceFill``
- ``Hyperliquid/TwapHistoryEntry``

### Streams

- ``Hyperliquid/StreamAPI``
- ``Hyperliquid/BestBidOffer``
- ``Hyperliquid/Batch``
- ``Hyperliquid/UserEvent``
- ``Hyperliquid/LiquidationID``

### Compressed feeds

- ``Hyperliquid/StreamAPI/orderBookUpdates(_:precision:)``
- ``Hyperliquid/StreamAPI/prices()``
- ``Hyperliquid/StreamAPI/assetContexts()``
- ``Hyperliquid/MarketPrices``

### Request weights and response sizes

- ``Hyperliquid/RequestWeight``
- ``Hyperliquid/ResponseSize``

### Errors and nonces

- ``HyperliquidError``
- ``Hyperliquid/ClientError``
- ``Hyperliquid/OrderAPI/invalidate(nonce:expiresAfter:)``

### Licenses

- <doc:ThirdPartyLicenses>

### Namespace

- ``Hyperliquid``
