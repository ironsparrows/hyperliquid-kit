# ``HyperliquidKitCore``

The models, requests, errors and domain protocols of HyperliquidKit, without the client.

## Overview

Apps import `HyperliquidKit`, which includes everything here and adds the client,
`Hyperliquid.Client`, which implements every domain protocol, and `Hyperliquid.PrivateKeySigner`.
Import `HyperliquidKitCore` alone in a module that only passes Hyperliquid's values around, signs
with its own ``Hyperliquid/Signer``, or mocks a domain, such as a ``Hyperliquid/MarketAPI`` in
tests, so it doesn't compile or link the networking and cryptography dependencies.
