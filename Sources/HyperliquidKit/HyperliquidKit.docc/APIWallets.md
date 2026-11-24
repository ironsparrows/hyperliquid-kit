# API wallets

Sign actions with an API wallet's key instead of the account's own, and read the account by its own
address.

## Overview

An API wallet, which Hyperliquid also calls an agent wallet, is a key that an account approves on
Hyperliquid to sign for it, or for its sub-accounts and vaults. Its key can stay on the device or
server that trades, while the account's own key stays elsewhere.

### What a client signs

HyperliquidKit signs trading actions: placing, changing and canceling orders, scheduling a cancel of
all orders, spending a nonce, setting leverage, moving isolated margin, and placing and canceling
TWAP orders. It doesn't implement transfers, withdrawals or approving API wallets; do those outside
this SDK.

``Hyperliquid/PrivateKeySigner`` signs with a key in memory. Conform your own type to
``Hyperliquid/Signer`` to sign elsewhere, such as in a hardware wallet or a remote signing service.

### Why the account matters

An API wallet only signs. Its own address holds nothing, so reads and streams for it come back
empty. Give the client the account's address, and the client reads and streams that account by
default:

```swift
let signer = try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey)
let client = Hyperliquid.Client(account: account, signer: signer)
```

Without an account, the client uses the signer's address, which is right only when the signer is the
account's own key. To trade for a sub-account or a vault, set its address as the vault. The vault then
replaces the account: actions trade for it, and reads and streams given no address read it.

```swift
let client = Hyperliquid.Client(
    signer: try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey), configuration: .init(vaultAddress: vault)
)
```

### Nonces

Hyperliquid tracks nonces per signer: per API wallet, whichever account it signs for. It keeps each
signer's 100 highest nonces, and accepts a new one only if it is higher than the lowest of them, unused,
and within 2 days before to 1 day after the block's time. The client starts each signer's nonces at the
device's current time in milliseconds and counts up, one counter per signer and network for the whole
process. So clients that share a signer in one process don't collide, but separate processes signing
with the same API wallet can, and a device clock that is far off, or set back, gets actions rejected.
Hyperliquid suggests one API wallet per trading process, and one per sub-account traded in parallel.

Hyperliquid may forget an API wallet, with the nonces it used, when it expires, when the account no
longer has funds, or when it is deregistered: approving a new unnamed API wallet deregisters the
account's existing unnamed one, and approving a named one deregisters the one with that name. A
deregistered API wallet's signatures stop working; if its address is approved again after its nonces
are forgotten, actions it signed before could be replayed. Don't reuse an API wallet's address:
approve a new one instead.
