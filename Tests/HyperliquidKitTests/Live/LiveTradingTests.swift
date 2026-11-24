import Testing

extension HyperliquidKitTests {
    // The suites that trade on mainnet, run one at a time so that one's leverage change or close
    // never meets another's BTC position or order.
    @Suite("Live trading", .serialized)
    struct LiveTradingTests {}
}
