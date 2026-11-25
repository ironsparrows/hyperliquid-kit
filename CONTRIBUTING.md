# Contributing

Read [ARCHITECTURE.md](ARCHITECTURE.md) first: it lists the targets, the access rules and the words the code uses.

## Requirements

Swift 6.4 or later. On macOS, Xcode 27.2 or later for the iOS build.

Platforms: macOS 13, iOS 16, tvOS 16 and visionOS 1, and Linux, a target platform not yet built or tested. watchOS is not supported.

On Linux, the compressed streams decode through the system's zlib, so building needs zlib's development headers, such as `zlib1g-dev` on Debian and Ubuntu.

## Checks before a change lands

Run them in a clean copy of the repository, so a local settings file and its keys never take part:

```bash
copy=$(mktemp -d) && git ls-files -z --cached --others --exclude-standard | rsync -a --from0 --files-from=- ./ "$copy"/ && cd "$copy"
```

Git ignores the local settings file, so the copy never has it. Stage a deleted tracked file (`git rm`) first: the copy stops at a listed file that is missing.

Then, from the copy. With `HYPERLIQUID_AGENT_KEY` and `HYPERLIQUID_ACCOUNT` set in the shell, `swift test` also runs the live suites, which trade on mainnet: unset them first, or add `--skip Live`.

```bash
swift format lint --strict -r Sources Tests Package.swift
```

```bash
swift build --build-tests -Xswiftc -warnings-as-errors
```

```bash
swift test
```

```bash
xcodebuild build -scheme HyperliquidKit -destination 'generic/platform=iOS'
```

```bash
xcodebuild docbuild -scheme HyperliquidKit -destination 'generic/platform=macOS'
```

The documentation build must show no warnings from `HyperliquidKit` or `HyperliquidKitCore`; the dependencies' own warnings are theirs. `HyperliquidKit`'s archive is the documentation apps read: it includes every `HyperliquidKitCore` type, which `HyperliquidKitCore`'s own archive repeats for modules that import it alone.

The code of the documentation's examples and the README's lives in `Tests/HyperliquidKitTests/PublicAPI/DocumentationExamples.swift`: `swift build --build-tests` compiles it, and `swift test` checks that each example's lines appear, in order, in one of its functions. Change both together.

Only this package's warnings can fail the build: SwiftPM suppresses warnings in dependencies.

Linux has no local check yet. `swift build` and `swift test` on Linux are unverified until CI or a Linux machine runs them, including the `HyperliquidKitTestSupport` target, which imports Testing.

## Formatting

swift-format reads `.swift-format`. Format the code before a pull request, and check it as CI does:

```bash
swift format -i -r Sources Tests Package.swift
```

```bash
swift format lint --strict -r Sources Tests Package.swift
```

The configuration is swift-language-models' with one difference: `AllPublicDeclarationsHaveDocumentation` is off, so an obvious stored property can go without a doc comment. A force unwrap or `try!` stays only with a `// swift-format-ignore: NeverForceUnwrap` (or `NeverUseForceTry`) comment and a line that says why it can't fail.

## Tests

- Swift Testing only: a root `@Suite` per test target with nested suites, one suite per file and the file named after it; sentence names in backticks; `@Test(arguments:)` for tables.
- Unit tests run offline. A live test calls Hyperliquid's mainnet: give its suite `.tags(.live)`, `.enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run")` and `.timeLimit(.minutes(2))`, and read the account and key from `LiveTestSettings.values`. Both come from `HyperliquidKitTestSupport`.
- Never put a private key in a committed file, a fixture or a log. The one exception is the Python SDK's published test key, which signs the signing vectors. Recordings use fake account addresses; public addresses such as a perp DEX's deployer stay as recorded.

### Running live tests

Live tests run when an API wallet's key and the account's address are set; otherwise they skip. There is no other switch: with them set, every live suite runs, including those that place real orders, in a plain `swift test` and in Xcode's Test action too. `swift test --skip Live` leaves them out.

**Five suites place small real orders on mainnet** with the API wallet, for the account, with real fees, in BTC. They run one at a time, nested in the "Live trading" suite. Each closes the size it ordered (Live order management, the size that filled) and cancels only its own orders; they add no checks or cleanup. Live order management also sets a cancel-all and clears it at once: if the clear fails, every open order on the account is canceled 60 seconds later. So use an account with no BTC position or orders of its own: a close reduces whatever BTC position is open, and switching BTC to isolated margin can fail with one open. A failure partway can leave a position or an order open, or BTC's leverage changed: check the account after a failed run, and after any run whose TWAP filled a slice before it was canceled, which leaves that position open.

| Suite | What it does |
|---|---|
| Live metadata | Reads the perp DEXs and their perpetuals, and resolves asset IDs. |
| Live market data | Reads mids, books, trades, candles, funding and the perp DEXs' limits. |
| Live account state | Reads the account's state, balances, mode, fees, limits and history. |
| Live order history | Reads the account's orders, fills and TWAP history. |
| Live streams | Streams mids, books, best bids and offers, trades, candles, market state and the compressed feeds. |
| Live order actions | **Places an order:** rests a buy of about $11 of BTC 10% under the mid price, changes it and cancels it. |
| Live market orders | **Trades:** buys about $11 of BTC with a market order and closes that size. |
| Live leverage, margin and TWAP actions | **Trades:** sets BTC to 10× isolated; opens about $11 of BTC, adds $2 of margin and removes $1, closes that size, and sets BTC's leverage back; starts a $110 BTC TWAP over 7 days and cancels it. A slice that filled before the cancel stays open. |
| Live order management | **Places orders and trades:** rests a buy about 10% under the mid price with a client order ID, finds, modifies and cancels it by that ID; rests another with a take-profit and a stop-loss child, cancels it and checks the children went with it; buys about $14 of BTC, adds a take-profit 50% above and a stop-loss 20% below, cancels both and closes the size that filled; sets a cancel-all 60 seconds ahead and clears it, which Hyperliquid refuses until the account has traded $1,000,000 and the test then records as a known issue; spends a nonce and checks Hyperliquid refuses it a second time. |
| Live account streams | **Trades:** streams the account while it buys about $11 of BTC with a market order and closes that size; the pushes must decode. |

Set them in the environment, reading the key without echo so it stays out of your shell history:

```bash
printf 'API wallet key: ' && read -rs HYPERLIQUID_AGENT_KEY && echo && export HYPERLIQUID_AGENT_KEY && export HYPERLIQUID_ACCOUNT=0xYourAccountAddress
```

```bash
swift test --filter Live
```

Or, to run them from Xcode without environment variables, create `Tests/HyperliquidKitTestSupport/LocalLiveTestSettings.swift`. Git ignores it; never commit it. Keep the names and types exactly as shown, or the values don't replace the empty defaults and the tests skip:

```swift
extension LocalLiveTestSettings {
    static let account = ""
    static let agentKey = ""
}
```

Never put the key in an Xcode scheme's environment variables: a shared scheme is a file that can be committed.

Values set in the environment win over the file's: when either is set there, the file isn't read. The two are always taken together from one place. Without the file, the package builds and live tests skip. The values are compiled into the build folders (`.build`, DerivedData), so delete those before sharing them.

## CI

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`: on macOS, the format lint, the build with warnings as errors and `swift test`; on Linux, in the `swift:6.4` container with zlib's headers, the same build and `swift test`. The iOS, tvOS and visionOS builds and the documentation build run before each release. CI has no keys, so the live suites skip there; they run only on your machine.

## Releases

A pull request's label decides the release its merge makes:

| Label | Release | Example |
|---|---|---|
| `release:patch` | a fix | 0.1.0 to 0.1.1 |
| `release:minor` | a new feature | 0.1.0 to 0.2.0 |
| `release:major` | a breaking change | 0.1.0 to 0.2.0 before 1.0, and 1.2.0 to 2.0.0 after it |
| none | nothing | |

When a labeled pull request merges into `main`, `.github/workflows/release.yml` first builds and tests on macOS and Linux, builds for iOS, tvOS and visionOS, and builds the documentation. Only when all of them pass does it tag the next version, publish a GitHub release whose notes group the merged pull requests by these labels (`.github/release.yml`), and start `.github/workflows/documentation.yml`, which publishes that release's documentation to GitHub Pages. Running the release workflow by hand from `main`, with the bump to apply, does the same. The workflow tags no version before the first, so `0.1.0` is released by hand, as a GitHub release rather than a bare tag, since the documentation workflow publishes the latest release; then start the documentation workflow. `1.0.0` is released by hand too.

```bash
gh release create 0.1.0 --target <commit on main> --generate-notes
```

```bash
gh workflow run documentation.yml --ref main
```

The labels `release:patch`, `release:minor` and `release:major` must exist in the repository. GitHub Pages must be set to deploy from GitHub Actions, and on a private repository it needs a paid GitHub plan for the organization; until then the documentation workflow fails and releases still tag and publish.

## Commits

Conventional Commits with a short summary, one feature per commit.
