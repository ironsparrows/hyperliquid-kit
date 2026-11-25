## What changed and why



## Checklist

- [ ] `swift format lint --strict -r Sources Tests Package.swift` passes.
- [ ] The checks in [CONTRIBUTING.md](https://github.com/ironsparrows/hyperliquid-kit/blob/main/CONTRIBUTING.md#checks-before-a-change-lands) pass in a clean copy:
      the build with warnings as errors, `swift test`, the iOS build and the documentation build.
- [ ] Every request, field, default and behavior follows Hyperliquid's official SDKs or API docs, with the source named.
- [ ] New behavior has tests; Hyperliquid's answers have recordings, with fake account addresses.
- [ ] New public types and methods have DocC comments, as do properties whose name doesn't say it all.
- [ ] An example changed in the README or an article is changed in `DocumentationExamples.swift` too.
- [ ] No private key, API wallet key or `LocalLiveTestSettings.swift` is committed.
- [ ] A maintainer adds `release:patch`, `release:minor` or `release:major` to release this change on merge.
