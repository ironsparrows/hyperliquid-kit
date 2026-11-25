extension Hyperliquid {
    /// The elements of one push on a stream that starts with a snapshot, such as an account's fills.
    ///
    /// The first push after subscribing is a snapshot of recent elements; the pushes after it hold
    /// new ones. A snapshot can repeat elements the app has already read, for example when it
    /// subscribes again after the connection dropped. Only the stream that starts a subscription gets
    /// its snapshot: a stream that joins one already streaming starts with the next new elements.
    public struct Batch<Element: Sendable>: Sendable {
        /// Whether the push is the snapshot sent when subscribing. Hyperliquid's `isSnapshot`.
        public let isSnapshot: Bool
        public let elements: [Element]

        public init(isSnapshot: Bool, elements: [Element]) {
            self.isSnapshot = isSnapshot
            self.elements = elements
        }
    }
}

extension Hyperliquid.Batch: Equatable where Element: Equatable {}
extension Hyperliquid.Batch: Hashable where Element: Hashable {}
