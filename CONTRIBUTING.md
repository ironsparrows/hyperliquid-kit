# Contributing

Read [ARCHITECTURE.md](ARCHITECTURE.md) first: it lists the targets, the access rules and the words the code uses.

## Requirements

Swift 6.4 or later. On macOS, Xcode 27.2 or later for the iOS build.

Supported platforms: macOS 13, iOS 16, tvOS 16, visionOS 1 and Linux. watchOS is not supported.

On Linux, the compressed streams decode through the system's zlib, so building needs zlib's development headers, such as `zlib1g-dev` on Debian and Ubuntu.

## Checks before a change lands

Run them in a clean copy of the repository, so a local settings file and its keys never take part:

```bash
copy=$(mktemp -d) && git ls-files -z --cached --others --exclude-standard | rsync -a --from0 --files-from=- ./ "$copy"/ && cd "$copy"
```

Git ignores the local settings file, so the copy never has it. Stage a deleted tracked file (`git rm`) first: the copy stops at a listed file that is missing.

Then, from the copy:

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

Linux is a supported platform but has no local check yet. `swift build` and `swift test` on Linux are unverified until CI or a Linux machine runs them, including the `HyperliquidKitTestSupport` target, which imports Testing.

## Tests

- Swift Testing only: a root `@Suite` per test target with nested suites, one suite per file and the file named after it; sentence names in backticks; `@Test(arguments:)` for tables.
- Unit tests run offline. A live test calls Hyperliquid's mainnet: give its suite `.tags(.live)`, `.enabled(if: areLiveTestsEnabled, "Set HYPERLIQUID_AGENT_KEY and HYPERLIQUID_ACCOUNT to run")` and `.timeLimit(.minutes(2))`, and read the account and key from `LiveTestSettings.values`. Both come from `HyperliquidKitTestSupport`.
- Never put a private key in a committed file, a fixture or a log. The one exception is the Python SDK's published test key, which signs the signing vectors. Recordings use fake account addresses; public addresses such as a perp DEX's deployer stay as recorded.

### Running live tests

Live tests run when an API wallet's key and the account's address are set; otherwise they skip. There is no other switch. Any live test that places orders runs with them too, so use an account you accept that for.

Set them in the environment, reading the key without echo so it stays out of your shell history:

```zsh
read -rs "HYPERLIQUID_AGENT_KEY?API wallet key: " && export HYPERLIQUID_AGENT_KEY && export HYPERLIQUID_ACCOUNT=0xYourAccountAddress
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

Values set in the environment win over the file's: when either is set there, the file isn't read. The two are always taken together from one place. Without the file, the package builds and live tests skip. The values are compiled into the build folders (`.build`, DerivedData), so delete those before sharing them.

## Commits

Conventional Commits with a short summary, one feature per commit.
