extension Hyperliquid {
    /// What happened to one order of a cancellation.
    public struct CancelResult: Hashable, Sendable {
        /// Hyperliquid's reason when the order wasn't canceled, such as
        /// `Order was never placed, already canceled, or filled.`; `nil` when it was.
        public let error: String?

        public init(error: String?) {
            self.error = error
        }

        public var isCanceled: Bool { error == nil }
    }
}

// MARK: - Wire

extension Hyperliquid.CancelResult: Decodable {
    /// `"success"`, or `{"error": "…"}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let status = try? container.decode(String.self) {
            self.init(error: status == "success" ? nil : status)
            return
        }
        struct Failure: Decodable {
            let error: String
        }
        self.init(error: try container.decode(Failure.self).error)
    }
}
