<div align="center">

# HyperliquidKit

**A Swift SDK for Hyperliquid's perpetuals.**

Market data, the account, orders, leverage, margin, TWAP orders and live streams, with `async`/`await` and exact
`Decimal` prices.

[![CI](https://github.com/ironsparrows/hyperliquid-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/ironsparrows/hyperliquid-kit/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ironsparrows/hyperliquid-kit)](https://github.com/ironsparrows/hyperliquid-kit/releases/latest)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2013%20%C2%B7%20iOS%2016%20%C2%B7%20tvOS%2016%20%C2%B7%20visionOS%201%20%C2%B7%20Linux-blue)](#installation)
[![License](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)

[Quick start](#quick-start) ·
[Installation](#installation) ·
[Usage](#usage) ·
[Testing](#testing) ·
[Docs](#documentation) ·
[Contributing](#contributing)

</div>

> [!TIP]
> **Trade on testnet first.** On mainnet, the default, actions trade real money. Pass
> `configuration: .init(network: .testnet)` to try them with test funds, then start on mainnet with small amounts.

HyperliquidKit calls Hyperliquid's `/info` and `/exchange` endpoints and its WebSocket streams, following Hyperliquid's
official Python SDK and API docs. It covers perpetuals, on the first perp DEX and on builder-deployed ones.
HyperliquidKit is not affiliated with Hyperliquid.

- **One client, one protocol per domain.** `client.market`, `client.account`, `client.position`, `client.order`,
  `client.twap` and `client.stream`, so tests can mock what they use.
- **Exact numbers.** Prices, sizes and amounts are `Decimal`, read exactly as Hyperliquid sends them.
- **Signed by an API wallet or your own signer.** Actions are signed by a `Signer`: an API wallet's key held by the
  app, or a type of your own that signs the finished digest. Nonces are counted per signer.
- **Orders.** Limit, trigger and market orders, closing positions, modify, cancel, scheduled cancel and nonce spending.
- **Leverage, margin and TWAP.** Cross and isolated leverage, isolated margin, and TWAP orders.
- **Streams over one WebSocket.** Market and account streams as `AsyncThrowingStream`s, plus the compressed feeds.
- **Errors that say who failed.** `HyperliquidError` when Hyperliquid refuses a call, with its message;
  `Hyperliquid.ClientError` when the client couldn't complete it. Canceling a call throws `CancellationError`.
- **Swift 6.4.** Strict concurrency and `async`/`await` throughout.

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

## Installation

- Swift 6.4 or later, and Xcode 27.2 or later on Apple platforms.
- macOS 13, iOS 16, tvOS 16 or visionOS 1. watchOS is not supported.
- Linux is a target platform that isn't built or tested yet. It needs zlib's development headers, such as
  `zlib1g-dev` on Debian and Ubuntu.

Add the package with Swift Package Manager, then add the `HyperliquidKit` product to your target:

```swift
.package(url: "https://github.com/ironsparrows/hyperliquid-kit.git", from: "0.1.0"),
```

```swift
.product(name: "HyperliquidKit", package: "hyperliquid-kit"),
```

In an Xcode project, use File > Add Package Dependencies and enter the repository URL.

`HyperliquidKitCore` is a second product with only the protocols and models, for a module that mocks the client or
signs with a signer of its own without compiling the networking and signing libraries.

## Usage

A market order is an immediate-or-cancel limit order at the mid price moved by a slippage, 5% by default:

```swift
// A market buy pays at most about the mid price plus 5%, unless you pass another slippage.
let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
guard let filled = opened.first?.filledSize, filled > 0 else { return }

// Sells what was bought with a reduce-only market order.
let closed = try await client.order.close("BTC", size: filled)
print(closed.first?.averagePrice ?? 0)
```

The account's fills, orders, positions and balances stream for the client's account. Fills, funding payments, the
ledger and the TWAP streams yield a batch per push, which marks the snapshot of recent ones that a new subscription
gets first:

```swift
for try await batch in client.stream.fills() where !batch.isSnapshot {
    for fill in batch.elements {
        print(fill.coin, fill.side, fill.price, fill.size)
    }
}
```

When the connection drops, every stream ends with an error and nothing reconnects: start the streams again, and read
anything you may have missed.

The [getting-started guide](Sources/HyperliquidKit/HyperliquidKit.docc/GettingStarted.md) walks through creating a
client, placing and canceling an order, opening and closing a position, streaming and handling errors.
[API wallets](Sources/HyperliquidKit/HyperliquidKit.docc/APIWallets.md) explains what a client signs, why the account
matters and how nonces work.

## Testing

`swift test` runs offline. The live suites call Hyperliquid's mainnet and run only when an API wallet's key and the
account's address are set; otherwise they skip, as they do in CI. **Five of them place small real orders, with real
fees.** [CONTRIBUTING.md](CONTRIBUTING.md#running-live-tests) says what each suite does, how to set the key without
echoing it, and which account to use.

## Documentation

The DocC catalog covers every type, a getting-started guide and API wallets. Once GitHub Pages is set up for the
repository, each release publishes it to
[GitHub Pages](https://ironsparrows.github.io/hyperliquid-kit/documentation/hyperliquidkit). Build it in Xcode with
Product > Build Documentation, or:

```bash
xcodebuild docbuild -scheme HyperliquidKit -destination 'generic/platform=macOS'
```

## Contributing

Ask questions and share ideas in [Discussions](https://github.com/ironsparrows/hyperliquid-kit/discussions), and report
bugs in [Issues](https://github.com/ironsparrows/hyperliquid-kit/issues). Pull requests are welcome; for a larger
change, open an issue first. [CONTRIBUTING.md](CONTRIBUTING.md) lists the checks, the live tests, the formatting and
the release labels, and [ARCHITECTURE.md](ARCHITECTURE.md) the layout and vocabulary.

## Related projects

- [MexcKit](https://github.com/ironsparrows/mexc-kit): the same kind of SDK for MEXC's futures.
- [Swift Language Models](https://github.com/ironsparrows/swift-language-models): one Foundation Models API for every
  provider's language models.

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE).

HyperliquidKit uses CryptoSwift, whose license requires an app that ships it to acknowledge it in the product's
documentation, and every distribution to keep this sentence and CryptoSwift's license notice:

> This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/).

Its other dependencies are mostly under the MIT and Apache 2.0 licenses; the
[Third-party licenses](Sources/HyperliquidKit/HyperliquidKit.docc/ThirdPartyLicenses.md) article lists them, and each
package's LICENSE and NOTICE files say what it requires.
