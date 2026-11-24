import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Nonce source")
    struct NonceSourceTests {
        private let signer: Hyperliquid.Address = "0x14791697260e4c9a71f18484c9f997b308e59325"
        private let other: Hyperliquid.Address = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"

        @Test func `a signer's first nonce is the current time`() async {
            #expect(await NonceSource { 1_700_000_000_000 }.next(for: signer, on: .mainnet) == 1_700_000_000_000)
        }

        @Test func `nonces in the same millisecond still increase`() async {
            let source = NonceSource { 1_700_000_000_000 }
            let nonces = [await source.next(for: signer, on: .mainnet), await source.next(for: signer, on: .mainnet)]
            #expect(nonces == [1_700_000_000_000, 1_700_000_000_001])
        }

        @Test func `each signer and network counts on its own`() async {
            let source = NonceSource { 5 }
            _ = await source.next(for: signer, on: .mainnet)
            #expect(await source.next(for: other, on: .mainnet) == 5)
            #expect(await source.next(for: signer, on: .testnet) == 5)
        }

        @Test func `concurrent actions never share a nonce`() async {
            let source = NonceSource { 5 }
            let nonces = await withTaskGroup(of: UInt64.self) { group in
                for _ in 0..<100 { group.addTask { [signer] in await source.next(for: signer, on: .mainnet) } }
                return await group.reduce(into: Set<UInt64>()) { $0.insert($1) }
            }
            #expect(nonces.count == 100)
        }
    }
}
