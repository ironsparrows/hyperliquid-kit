# Getting started

Create a client, read market data, place and cancel an order, open and close a position, stream a
book and handle errors.

## Overview

Add `HyperliquidKit` to your target, and import it with Foundation, which the examples use for
`Decimal`.

> Important: On mainnet, which is the default, actions trade real money. Try them on testnet first.

### Create a client

A client that trades needs two things: the account's address, and a signer for its actions. The
signer is usually an API wallet's key, approved for the account on Hyperliquid; see
<doc:APIWallets>. Load the key from the Keychain or the environment when the app runs, and never
write it in code.

```swift
let signer = try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey)
let client = Hyperliquid.Client(account: account, signer: signer, configuration: .init(timeout: .seconds(10)))

// Market data and market streams need neither an account nor a signer.
let publicClient = Hyperliquid.Client()

// Testnet trades with test funds: the account needs them, and the API wallet approved, on testnet.
let testnetClient = Hyperliquid.Client(account: account, signer: signer, configuration: .init(network: .testnet))
```

Without a ``Hyperliquid/Client/Configuration/timeout``, a request has no time limit beyond 10
seconds to connect, so set one for a client that trades.
``Hyperliquid/PrivateKeySigner/init(hexKey:)`` takes the key with or without `0x`, and throws
``Hyperliquid/ClientError/Reason/invalidPrivateKey`` for anything else, without repeating the key.
A client without a signer throws ``Hyperliquid/ClientError/Reason/missingSigner`` from actions, and
one without an account or signer throws ``Hyperliquid/ClientError/Reason/missingAccount`` from
account reads, both before sending anything.

Keep one client for the app: it holds the stream connection and the perpetuals it has looked up.

### Read mid prices

```swift
let mids = try await client.market.mids()
print(mids["BTC"] ?? 0)
```

Coins are string literals of ``Hyperliquid/Coin``, spelled as Hyperliquid spells them: `"BTC"` on
the first perp DEX, `"xyz:XYZ100"` on a builder-deployed one. Prices and sizes are `Decimal`;
build your own from strings or integers, such as `Decimal(string: "0.9")!`, because a
floating-point literal isn't exact as a `Decimal`.

### Place and cancel an order

Hyperliquid accepts a perpetual's price with at most 5 significant figures and at most
`6 − sizeDecimals` decimals, or any whole number; a size with at most the perpetual's
``Hyperliquid/Perpetual/sizeDecimals`` decimals; and an order worth at least $10. Rounding to whole
dollars suits a high-priced coin such as BTC; round others to 5 significant figures and the allowed
decimals instead.

```swift
guard let mid = try await client.market.mids()["BTC"],
    let btc = try await client.market.perpetuals().first(where: { $0.coin == "BTC" })
else { return }

// A buy 10% under the mid price rests in the book. BTC's price in whole dollars is always
// valid, and an order must be worth at least $10.
var exactPrice = mid * Decimal(string: "0.9")!
var price = Decimal()
NSDecimalRound(&price, &exactPrice, 0, .down)
var exactSize = Decimal(11) / price
var size = Decimal()
NSDecimalRound(&size, &exactSize, btc.sizeDecimals, .up)

let placed = try await client.order.place([
    .limit(.buy, "BTC", price: price, size: size, timeInForce: .addLiquidityOnly)
])
guard let id = placed.first?.orderID else {
    print("Not placed:", placed.first?.error ?? "")
    return
}
let canceled = try await client.order.cancel([.init(id, coin: "BTC")])
print(canceled.first?.isCanceled == true ? "Canceled" : canceled.first?.error ?? "")
```

Each order gets its own ``Hyperliquid/PlacementResult``, and each cancel its own
``Hyperliquid/CancelResult``: a rejected order or a failed cancel doesn't throw, and its result
carries Hyperliquid's reason. ``Hyperliquid/OrderRequest`` also builds trigger orders, and
``Hyperliquid/OrderAPI/modify(_:alwaysPlace:expiresAfter:)`` replaces orders in place.

### Open and close a position

A market order is an immediate-or-cancel limit order at the mid price moved by a slippage, 5% by
default:

```swift
// A market buy pays at most about the mid price plus 5%, unless you pass another slippage.
let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
guard let filled = opened.first?.filledSize, filled > 0 else { return }

// Sells what was bought with a reduce-only market order.
let closed = try await client.order.close("BTC", size: filled)
print(closed.first?.averagePrice ?? 0)
```

``Hyperliquid/OrderAPI/close(_:size:price:slippage:clientID:expiresAfter:)`` acts on the account's
whole position in the coin, not on one order: it reduces whatever position is open, and leaving out
the size closes all of it.

Leverage, isolated margin and TWAP orders have their own domains, `client.position` and
`client.twap`. Until one of those actions commits, Hyperliquid deprioritizes the account's actions,
and those of its sub-accounts and the vaults it leads, in standard account mode; send them sparingly.

### Stream a book

Streams are `AsyncThrowingStream`s, over one WebSocket connection the client opens with the first
stream. A stream subscribes when it's made, unless another stream already did, and the subscription
ends with the last stream that uses it:

```swift
for try await book in client.stream.orderBook("BTC") {
    print(book.bids.first?.price ?? 0, book.asks.first?.price ?? 0)
}
```

The account's fills, orders, positions and balances stream the same way, for the client's account.
Fills, funding payments, the ledger and the TWAP streams yield a ``Hyperliquid/Batch`` per push,
which marks the snapshot of recent ones that the stream starting a subscription gets first:

```swift
for try await batch in client.stream.fills() where !batch.isSnapshot {
    for fill in batch.elements {
        print(fill.coin, fill.side, fill.price, fill.size)
    }
}
```

When the connection drops, every stream ends with ``Hyperliquid/ClientError/Reason/connectionClosed``,
or ``Hyperliquid/ClientError/Reason/connectionFailed`` when it couldn't open, and nothing reconnects:
start the streams again, and read anything you may have missed.

### Handle errors

A call throws ``HyperliquidError`` when Hyperliquid refuses it or answers in a way the client can't
use, and ``Hyperliquid/ClientError`` when the client couldn't complete it, such as when Hyperliquid
doesn't answer in time. Given an order `order`:

```swift
do {
    // A rejected order doesn't throw: its result says why.
    for result in try await client.order.place([order]) where result.status == .rejected {
        print("Hyperliquid rejected the order:", result.error ?? "")
    }
} catch let error as HyperliquidError where error.kind == .actionRejected {
    print("Hyperliquid rejected the action:", error.message ?? "")
} catch {
    // Another failure after sending, such as a timeout, can leave the outcome unknown. Spending
    // the nonce stops the action if it hasn't executed.
    print(error.localizedDescription)
    if let nonce = (error as? Hyperliquid.ClientError)?.nonce ?? (error as? HyperliquidError)?.nonce {
        try await client.order.invalidate(nonce: nonce)
    }
}
```

Every action is signed with a nonce. An action that times out, loses its connection, or gets an
answer the client can't read may still execute, and its error carries the nonce.
``Hyperliquid/OrderAPI/invalidate(nonce:expiresAfter:)`` spends that nonce: if it succeeds, the
action can no longer execute; if Hyperliquid rejects it with
``HyperliquidError/Kind-swift.struct/actionRejected``, the nonce was already used, most likely by the
action. If the invalidation itself fails on the network, its outcome is unknown too. Either way,
read the orders and fills before trying again. Canceling the task
that waits for an action throws `CancellationError`, which carries no nonce: the action may still
execute.
