public import Foundation

/// A failure Hyperliquid reported, or a response the client couldn't use.
///
/// Hyperliquid sends no error codes: ``kind`` says what failed and ``message`` carries Hyperliquid's
/// text. ``description`` leaves out ``body``, which can hold account data.
///
/// `localizedDescription` is Hyperliquid's message, or a sentence about ``kind`` when there is none.
public struct HyperliquidError: Error, Sendable, CustomStringConvertible {
    public var kind: Kind
    /// Hyperliquid's text, such as `Order must have minimum value of $10.`
    public var message: String?
    public var httpStatus: Int?
    /// The raw response body, for diagnostics.
    public var body: Data?
    /// The nonce of the action that failed. While it is unused, the action could still execute;
    /// using the nonce for another action makes sure it never does.
    public var nonce: UInt64?

    public init(_ kind: Kind, message: String? = nil, httpStatus: Int? = nil, body: Data? = nil, nonce: UInt64? = nil) {
        self.kind = kind
        self.message = message
        self.httpStatus = httpStatus
        self.body = body
        self.nonce = nonce
    }

    public var description: String {
        var text = "Hyperliquid error \(kind)"
        if let httpStatus { text += " (HTTP \(httpStatus))" }
        if let message, !message.isEmpty { text += ": \(message)" }
        return text
    }
}

extension HyperliquidError: LocalizedError {
    public var errorDescription: String? {
        if let message, !message.isEmpty { return message }
        return kind.summary
    }
}

extension HyperliquidError {
    /// What failed.
    public struct Kind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public var description: String { rawValue }

        /// Hyperliquid rejected the whole action, such as a signature it couldn't match or a batch
        /// that failed validation.
        public static let actionRejected = Self(rawValue: "actionRejected")
        /// Hyperliquid answered with an HTTP status of 400 or more, such as 500 for an unknown coin.
        public static let httpStatus = Self(rawValue: "httpStatus")
        /// Hyperliquid's response doesn't have the shape the request expects.
        public static let unexpectedResponse = Self(rawValue: "unexpectedResponse")

        fileprivate var summary: String {
            switch self {
            case .actionRejected: "Hyperliquid rejected the action"
            case .httpStatus: "Hyperliquid answered with an HTTP error"
            case .unexpectedResponse: "Hyperliquid's response has an unexpected shape"
            default: "Hyperliquid error \(rawValue)"
            }
        }
    }
}
