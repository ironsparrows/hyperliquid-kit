# Architecture

HyperliquidKit is a Swift SDK for Hyperliquid perpetuals: market data, account state, orders and positions over the `/info` and `/exchange` endpoints, and the WebSocket streams. This file is for contributors.

## Targets

```text
Your app
└── HyperliquidKit          product; the live client over REST and WebSocket and the private-key signer; re-exports HyperliquidKitCore
    └── HyperliquidKitCore  product; the contract: namespace, models, vocabularies, protocols (including `Signer` and `SigningRequest`), errors
```

- Dependencies point one way: app, `HyperliquidKit`, `HyperliquidKitCore`, platform.
- `HyperliquidKitCore` depends only on Foundation. It is a product so a module that needs only the contract (protocols and models, for mocking or dependency injection, or a signer of its own) doesn't compile NIO, BoringSSL or the signing libraries.
- `HyperliquidKit` depends on AsyncHTTPClient (REST), WebSocketKit (streams), P256K from swift-secp256k1 (recoverable ECDSA signatures), CryptoSwift (Keccak-256) and GzipSwift (raw DEFLATE for the compressed streams, through the system's zlib). None of their types appears in a public signature: `import HyperliquidKit` is all an app writes.
- Everything that turns an action into a digest (MessagePack encoding, Keccak-256, the action hash, EIP-712) lives in `HyperliquidKit`. A signer an app writes against `HyperliquidKitCore` receives the finished 32-byte digest.
- Every API type is nested in `Hyperliquid`, so names like `Order`, `Signer` or `Address` can't collide with an app's types, another exchange SDK, or a dependency. Only `Hyperliquid` and `HyperliquidError` sit at the top level.

## Settings

Every target builds in the Swift 6 language mode with `ApproachableConcurrency`, `ExistentialAny`, `InternalImportsByDefault` and `MemberImportVisibility`. Code is nonisolated by default: no target sets a default actor isolation, so an app on any actor can call the SDK. Mark CPU-heavy work, such as decoding large responses or inflating compressed frames, `@concurrent` so it leaves the caller's actor.

Shared mutable state lives in an actor, one per piece of state. Library code uses no `@unchecked Sendable` and no `nonisolated(unsafe)`.

Import `Foundation` with a plain `import Foundation`, not `FoundationEssentials`. Write `public import Foundation` only in a file whose public signatures use a Foundation type.

Some dependencies export the same top-level names:

- Import CryptoSwift in one file only, the Keccak-256 wrapper.
- Never import `P256K` together with `Crypto` or `CryptoSwift` in one file: P256K re-exports CryptoKit on Apple platforms and has its own `SHA256`, and CryptoSwift has its own `Digest` and `Signature`.

## Platforms

macOS 13, iOS 16, tvOS 16, visionOS 1 and Linux. watchOS is not supported.

The three deflate-compressed streams (`l2` order book diffs, `fastAssetCtxs` and `pac`) decode with GzipSwift on every platform: `gunzipped(wBits: -15)` reads raw DEFLATE. Only `Streams/Inflate.swift` imports it. Each push is inflated once: an `l2` diff while it is routed, since its coin is inside it, and a `fastAssetCtxs` or `pac` push by its stream. Their pushes build on the snapshot sent on subscribing, so each streams to one reader at a time.

## Access

| Level | For |
|---|---|
| `public` | What apps use |
| `package` | What another target writes today |
| nothing written | The rest of a target. Never write `internal` |
| `private` | What one file uses, such as wire types and coding keys |

## Folders and files

- `HyperliquidKitCore` has one folder per property of `Hyperliquid.API`, named after it: `Market/`, `Account/`, `Position/`, `Order/`, `Twap/` and `Stream/`. Each holds its domain's protocol, such as `MarketAPI.swift`, then the models and request values its methods take or return. A model that a stream and a REST read share stays with the REST domain; `Stream/` holds `StreamAPI.swift` and the models only a stream pushes. The root holds the namespace (`Hyperliquid.swift`), `API.swift` and what three or more domains use: errors, addresses, coins, perp DEXs, identifiers, the network, the signer and the vocabulary. A file with no `public` declaration goes in `Internal/`.
- `HyperliquidKit`'s root holds only its public files: `Client.swift`, `Exports.swift` and `PrivateKeySigner.swift`. Its internals are grouped by mechanism:

  | Folder | Holds |
  |---|---|
  | `Endpoints/` | One conformer per REST domain, named `<Domain>Endpoints`, and the helpers only they use |
  | `Streams/` | `Streams`, the `StreamAPI` conformer, which forwards to `MarketStreams` and `AccountStreams`; the connection, its `StreamRouter`, and inflating compressed pushes |
  | `HTTP/` | Sending one request: the info and exchange clients |
  | `Signing/` | Everything that produces a signature: the action hash, EIP-712 typed data, Keccak-256 and the nonces it signs with |
  | `Shared/` | What several of the folders above use: the asset directory, account parameters, action values and their bytes, and an order book precision's parameters |
  | `Transport/` | The transport protocols and their conformers, the only files that import AsyncHTTPClient, NIOCore, NIOHTTP1 or WebSocketKit |
- A file owns one responsibility and is named after its primary type. Wire types live, `private`, in the file that reads or writes them.
- Tests mirror the sources: `HyperliquidKitCoreTests` for the contract, `HyperliquidKitTests` for the client, each a root suite with one nested suite per file; a test file sits in the folder of the source it tests. A few suites cover two neighboring domains, such as account and position reads, or order and TWAP reads, and `CompressedFeedsTests` covers the compressed feeds in `MarketStreams.swift` and their routing. `HyperliquidKitTestSupport` (in `Tests/`, not a product) holds the live test gate (`areLiveTestsEnabled`, `LiveTestSettings`), the `.live` tag and the recordings. In `HyperliquidKitTests`, `PublicAPI/` checks what apps see: the public surface, the client, the private-key signer and the documentation's examples; `Loopback/` sends real requests to a local server, `Live/` calls Hyperliquid's mainnet, and `Support/` holds fakes and helpers.
- `HyperliquidKitTestSupport/Fixtures/` holds what was recorded from Hyperliquid, byte for byte except account addresses and hashes, which are swapped for fakes. Responses are in the folder of the domain whose method reads them, named after their endpoint (`Market/meta.json`); pushes are in `Stream/`, named after their channel (`Stream/l2Book.json`), and compressed streams are one frame per line (`Stream/l2.jsonl`). Both test targets read them through `Fixture`. `.gitattributes` keeps every fixture byte for byte.
- `HyperliquidKit.docc` holds the documentation's landing page and articles; `HyperliquidKitCore.docc` holds the landing page of `HyperliquidKitCore` alone. The code of their examples and the README's lives in `Tests/HyperliquidKitTests/PublicAPI/DocumentationExamples.swift`, compiled but never run; `DocumentationExampleTests` checks each example matches it.

Files of one kind use the same `// MARK: -` sections in the same order; a section that doesn't apply is left out. Inside a type, plain `// MARK:` marks group its members by topic, such as a protocol's requirements (Perpetuals, Prices and trades, …) and the matching methods of its conformer.

| Kind | Sections |
|---|---|
| A domain protocol | its requirements by topic · Defaults |
| A model | the type · Wire |
| A domain conformer | its methods by topic, then Actions · Requests · Wire |
| The stream connection | plain marks inside the actor: Streams · Subscribing · Connection · Receiving · Inspecting · Wire; routing in `StreamRouter.swift` |
| `Streams` | plain marks: Markets · Compressed feeds · Account · Connection, each forwarding |
| `MarketStreams`, `AccountStreams` | their streams by topic, then what those streams share (Inflating, Subscribing), as plain marks · Subscriptions · Merging · Wire, as each file needs |

## Vocabulary

One word per concept in code, comments and docs.

| Word | Means | Hyperliquid names |
|---|---|---|
| perpetual | one perp market: its name and trading rules | `meta.universe[i]`, "asset", "coin" |
| coin | the market's name as Hyperliquid spells it, including a `dex:` prefix | `coin`, `name` |
| asset ID | the integer an action uses for a market | `a`, `asset` |
| perp DEX | a family of perp order books; `""` is the first, validator-operated one | `dex`, HIP-3 |
| account | the address whose state is read and traded | `user` |
| signer | the key that signs: the account's own or an API wallet | "API wallet", "agent wallet" |
| action | a signed write to `/exchange` | `action` |
| size | an amount in the base coin | `sz` |
| fill | one execution of the account's order | `userFills`, `fills` |
| trade | one public execution | `trades`, `recentTrades` |
| pending order | a resting or untriggered order | `openOrders`, "open orders" |
| perpetual state | positions and margin on one perp DEX | `clearinghouseState` |
| balance | a token balance in the spot clearinghouse | `spotClearinghouseState`, `spotState` |
| client order ID | the caller's own 16-byte order ID | `cloid`, `c` |
