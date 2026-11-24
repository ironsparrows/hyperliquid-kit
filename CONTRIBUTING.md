# Contributing

Read [ARCHITECTURE.md](ARCHITECTURE.md) first: it lists the targets, the access rules and the words the code uses.

## Requirements

Swift 6.4 or later. On macOS, Xcode 27.2 or later for the iOS build.

Supported platforms: macOS 13, iOS 16, tvOS 16, visionOS 1 and Linux. watchOS is not supported.

## Checks before a change lands

Run them from the package root:

```bash
swift build --build-tests -Xswiftc -warnings-as-errors
```

```bash
swift test
```

```bash
xcodebuild build -scheme HyperliquidKit -destination 'generic/platform=iOS'
```

Only this package's warnings can fail the build: SwiftPM suppresses warnings in dependencies.

Linux is a supported platform but has no local check yet. `swift build` and `swift test` on Linux are unverified until CI or a Linux machine runs them.

## Tests

- Swift Testing only: a root `@Suite` per test target with nested suites, one suite per file and the file named after it; sentence names in backticks; `@Test(arguments:)` for tables.
- Unit tests run offline. Tag read-only tests against the live Hyperliquid servers `.live` and skip them unless `HYPERLIQUID_LIVE=1` is set. They read public data, or an account's state by the address in `HYPERLIQUID_ACCOUNT`; none of them signs.
- Suites that place real orders are tagged `.liveOrders` and skip unless `HYPERLIQUID_LIVE_RUN` names the run and `HYPERLIQUID_ACCOUNT` and `HYPERLIQUID_AGENT_KEY` are set. Only the account owner runs them.
- Never put a private key in a file, fixture or log. The one exception is the Python SDK's published test key, which signs the signing vectors. Recordings use fake addresses.

## Commits

Conventional Commits with a short summary, one feature per commit.
