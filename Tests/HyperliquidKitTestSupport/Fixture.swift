package import Foundation
import Testing

/// Responses and frames recorded from Hyperliquid's mainnet API, byte for byte except replaced
/// addresses and hashes.
package enum Fixture {
    /// The folder a recording is in: the API domain whose method reads it, or the streams.
    package enum Folder: String, Sendable {
        case market = "Market"
        case account = "Account"
        case position = "Position"
        case order = "Order"
        case twap = "Twap"
        case stream = "Stream"
    }

    /// A recorded response or push, named after its endpoint or channel.
    package static func data(
        _ name: String, in folder: Folder, withExtension fileExtension: String = "json"
    ) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures/\(folder.rawValue)")
        )
        return try Data(contentsOf: url)
    }

    /// The frames of a recorded stream, one per line, in the order they arrived.
    package static func frames(_ name: String) throws -> [String] {
        String(decoding: try data(name, in: .stream, withExtension: "jsonl"), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }
}
