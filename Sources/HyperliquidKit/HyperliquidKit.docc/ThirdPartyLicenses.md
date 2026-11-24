# Third-party licenses

The open-source packages HyperliquidKit uses, and what an app that ships them owes their authors.

## Overview

An app that includes HyperliquidKit includes these packages too, and their licenses apply to it.

### CryptoSwift

HyperliquidKit hashes with CryptoSwift, by Marcin Krzyżanowski. Its license requires an app that
uses it to acknowledge it in the product's documentation, and every distribution to keep this
acknowledgment:

> This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/).

Put that sentence in your app's documentation or acknowledgments, and keep CryptoSwift's license
notice with any copy of its source or binaries.

### Others

These require keeping their copyright and license notices, and the NOTICE files of those under
Apache 2.0, with copies of the software:

- swift-secp256k1 (MIT), with libsecp256k1 (MIT), which signs.
- GzipSwift (MIT), which inflates the compressed streams.
- AsyncHTTPClient, SwiftNIO and websocket-kit (Apache 2.0 or MIT), which carry the requests and
  streams, and their dependencies, mostly under the same licenses; some, such as the BoringSSL that
  swift-nio-ssl and swift-crypto include, carry other notices. Each package's LICENSE and NOTICE
  files say what it requires.
