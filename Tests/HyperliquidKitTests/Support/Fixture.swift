import Foundation
import Testing

/// Frames and responses recorded from Hyperliquid's mainnet API, byte for byte.
enum Fixture {
    static func data(_ name: String, withExtension fileExtension: String = "json") throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    /// The frames of a recorded stream, one per line, in the order they arrived.
    static func frames(_ name: String) throws -> [String] {
        String(decoding: try data(name, withExtension: "jsonl"), as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
