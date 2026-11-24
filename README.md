# HyperliquidKit

A Swift SDK for Hyperliquid's perpetuals: market data, the account, orders and market orders,
leverage, margin and TWAP orders, and live market and account streams.

HyperliquidKit is not affiliated with Hyperliquid. On mainnet, the default, its actions trade real
money: try them on testnet (`configuration: .init(network: .testnet)`) first, then with small
amounts.

- Swift 6.4, strict concurrency, `async`/`await` throughout.
- Prices and sizes are `Decimal`, read exactly as Hyperliquid sends them.
- One protocol per domain, so tests can mock what they use.
- Actions are signed by a `Signer`: an API wallet's key held by the app, or your own type.
- Errors say who failed: `HyperliquidError` when Hyperliquid refuses a call, with its message;
  `Hyperliquid.ClientError` when the client couldn't complete it. Cancelling a call throws
  `CancellationError`.

## Requirements

Swift 6.4 or later (Xcode 27.2 or later on Apple platforms). macOS 13, iOS 16, tvOS 16 and
visionOS 1, and Linux, which isn't built or tested yet and needs zlib's development headers. watchOS
is not supported.

## Installation

HyperliquidKit isn't published yet. Until it is, add it to your package from a local checkout in a
folder named `HyperliquidKit`, then add the `HyperliquidKit` product to your target. The `package:`
argument is the checkout folder's name:

```swift
.package(path: "../HyperliquidKit"),
```

```swift
.product(name: "HyperliquidKit", package: "HyperliquidKit"),
```

In an Xcode project, use File > Add Package Dependencies > Add Local.

## Quick start

With the account's address and an API wallet approved for it on Hyperliquid:

```swift
// The API wallet's key comes from the Keychain or the environment, never from a literal.
let signer = try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey)
let client = Hyperliquid.Client(account: account, signer: signer)

let mids = try await client.market.mids()
print(mids["BTC"] ?? 0)

for try await book in client.stream.orderBook("BTC") {
    print(book.bids.first?.price ?? 0, book.asks.first?.price ?? 0)
}
```

Market data and market streams need neither an account nor a signer: `Hyperliquid.Client()`.

## Documentation

The DocC catalog covers every type, a getting-started guide (creating a client, placing and
canceling an order, opening and closing a position, streaming and handling errors) and API wallets.
Build it in Xcode with Product > Build Documentation, or:

```bash
xcodebuild docbuild -scheme HyperliquidKit -destination 'generic/platform=macOS'
```

## Licenses

HyperliquidKit uses CryptoSwift, whose license requires an app that ships it to acknowledge it in the
product's documentation, and every distribution to keep this sentence and CryptoSwift's license
notice:

> This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/).

Its other dependencies are mostly under the MIT and Apache 2.0 licenses; the Third-party licenses
article lists them, and each package's LICENSE and NOTICE files say what it requires.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the checks, the live tests and the commit style, and
[ARCHITECTURE.md](ARCHITECTURE.md) for the layout and vocabulary.
