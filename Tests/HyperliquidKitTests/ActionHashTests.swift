import Testing
@testable import HyperliquidKit

// nktkas/hyperliquid publishes these hashes in `tests/signing/mod.test.ts`; no key is involved.
extension HyperliquidKitTests {
    @Suite("Action hash")
    struct ActionHashTests {
        @Test(arguments: [
            (false, false, "0x25367e0dba84351148288c2233cd6130ed6cec5967ded0c0b7334f36f957cc90"),
            (true, false, "0x214e2ea3270981b6fd18174216691e69f56872663139d396b10ded319cb4bb1e"),
            (false, true, "0xc30b002ba3775e4c31c43c1dfd3291dfc85c6ae06c6b9f393991de86cad5fac7"),
            (true, true, "0x2d62412aa0fc57441b5189841d81554a6a9680bf07204e1454983a9ca44f0744"),
        ])
        func `the vault and expiry change the connection ID as the TypeScript SDK's vectors say`(
            withVault: Bool, withExpiry: Bool, expected: String
        ) {
            let order: ActionValue = [
                "type": "order",
                "orders": [["a": 0, "b": true, "p": "30000", "s": "0.1", "r": false, "t": ["limit": ["tif": "Gtc"]]]],
                "grouping": "na",
            ]
            let action = L1Action(
                action: order,
                nonce: 1_234_567_890,
                vault: withVault ? "0x1234567890123456789012345678901234567890" : nil,
                expiresAfter: withExpiry ? 1_234_567_890 : nil
            )
            #expect(hexadecimal(action.connectionID) == expected)
        }
    }
}
