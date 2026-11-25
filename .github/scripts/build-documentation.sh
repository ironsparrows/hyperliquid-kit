#!/usr/bin/env bash
# Builds the documentation site that GitHub Pages serves into ./site. Arguments go on to the documentation plugin.
set -euo pipefail

# Apps don't fetch the plugin: it is added to the manifest only here, for this build. The version is exact because
# the stand-in below depends on how this one runs docc.
echo 'package.dependencies.append(.package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0"))' >> Package.swift

# `HyperliquidKit` re-exports the core, and its symbol graphs lack the core's doc comments. A stand-in for docc puts
# them back. The plugin reads docc's features from beside what it runs, so they go there.
stand_in=$(mktemp -d)
mkdir "$stand_in/bin"
ln -s "$PWD/.github/scripts/docc-with-core-comments.py" "$stand_in/bin/docc"
ln -s "$(dirname "$(xcrun --find docc)")/../share" "$stand_in/share"
export DOCC_EXEC="$stand_in/bin/docc"

# `HyperliquidKit`'s documentation holds every type of the core, so the core needs no site of its own.
swift package --disable-sandbox --allow-writing-to-directory site generate-documentation \
  --target HyperliquidKit \
  --transform-for-static-hosting --hosting-base-path hyperliquid-kit \
  --output-path site "$@"

test -f site/documentation/hyperliquidkit/index.html

# A core type that lost its doc comment builds without a warning.
jq -e '.abstract | length > 0' site/data/documentation/hyperliquidkit/hyperliquid/marketapi.json > /dev/null

# DocC gives the site's root no page, so it sends visitors to the module's landing page.
cat > site/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>HyperliquidKit</title>
<meta http-equiv="refresh" content="0; url=documentation/hyperliquidkit/">
<link rel="canonical" href="documentation/hyperliquidkit/">
<a href="documentation/hyperliquidkit/">Documentation</a>
HTML
