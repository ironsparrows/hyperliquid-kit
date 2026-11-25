import Testing

@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("MessagePack")
    struct MessagePackTests {
        // Each row sits on a boundary of the MessagePack format, where the encoding grows.
        @Test(arguments: [
            (ActionValue.unsigned(0), "0x00"),
            (.unsigned(127), "0x7f"),
            (.unsigned(128), "0xcc80"),
            (.unsigned(255), "0xccff"),
            (.unsigned(256), "0xcd0100"),
            (.unsigned(65_535), "0xcdffff"),
            (.unsigned(65_536), "0xce00010000"),
            (.unsigned(4_294_967_295), "0xceffffffff"),
            (.unsigned(4_294_967_296), "0xcf0000000100000000"),
            (.unsigned(100_000_000_000), "0xcf000000174876e800"),
            (.signed(5), "0x05"),
            (.signed(-1), "0xff"),
            (.signed(-32), "0xe0"),
            (.signed(-33), "0xd0df"),
            (.signed(-128), "0xd080"),
            (.signed(-129), "0xd1ff7f"),
            (.signed(-32_768), "0xd18000"),
            (.signed(-32_769), "0xd2ffff7fff"),
            (.signed(-2_147_483_648), "0xd280000000"),
            (.signed(-2_147_483_649), "0xd3ffffffff7fffffff"),
            (.signed(.min), "0xd38000000000000000"),
            (.bool(true), "0xc3"),
            (.bool(false), "0xc2"),
            (.null, "0xc0"),
            (.string(""), "0xa0"),
            (.string("na"), "0xa26e61"),
        ])
        func `a scalar takes its smallest encoding`(value: ActionValue, expected: String) {
            #expect(hexadecimal(value.messagePack) == expected)
        }

        @Test(arguments: [(31, "0xbf"), (32, "0xd920"), (255, "0xd9ff"), (256, "0xda0100"), (65_536, "0xdb00010000")])
        func `a string's header grows with its UTF-8 length`(length: Int, header: String) {
            let bytes = ActionValue.string(String(repeating: "x", count: length)).messagePack
            #expect(hexadecimal(bytes.prefix(bytes.count - length)) == header)
        }

        @Test(arguments: [(15, "0x9f"), (16, "0xdc0010"), (65_536, "0xdd00010000")])
        func `an array's header grows with its count, so a batch of 16 orders uses array16`(count: Int, header: String) {
            let bytes = ActionValue.array(Array(repeating: .null, count: count)).messagePack
            #expect(hexadecimal(bytes.prefix(bytes.count - count)) == header)
        }

        @Test(arguments: [(15, "0x8f"), (16, "0xde0010")])
        func `a map's header grows with its count`(count: Int, header: String) {
            let entries = Array(repeating: ActionValue.Entry(key: "k", value: .null), count: count)
            let bytes = ActionValue.map(entries).messagePack
            #expect(hexadecimal(bytes.prefix(bytes.count - 3 * count)) == header)
        }

        @Test func `a map keeps its keys in the order they are written`() {
            let value: ActionValue = ["type": "cancel", "cancels": [["a": 0, "o": 1]]]
            #expect(
                hexadecimal(value.messagePack)
                    == "0x82a474797065a663616e63656ca763616e63656c739182a16100a16f01"
            )
        }
    }
}
