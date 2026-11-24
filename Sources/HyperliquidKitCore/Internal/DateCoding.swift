package import Foundation

/// An instant Hyperliquid sends as whole milliseconds since 1970, such as `1795507630703`.
package struct WireDate: Decodable {
    package let value: Date

    package init(from decoder: any Decoder) throws {
        value = Date(wireMilliseconds: try decoder.singleValueContainer().decode(Int64.self))
    }
}

extension Date {
    /// The instant `milliseconds` after 1970.
    init(wireMilliseconds milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// Whole milliseconds since 1970, rounded down, as Hyperliquid's requests take them.
    package var wireMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded(.down))
    }
}
