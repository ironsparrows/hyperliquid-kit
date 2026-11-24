import Foundation
import Testing

/// A response recorded from Hyperliquid's mainnet API, byte for byte.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
