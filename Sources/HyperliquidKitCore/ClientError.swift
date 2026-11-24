public import Foundation

extension Hyperliquid {
    /// A failure the client detected itself, as opposed to one Hyperliquid reported
    /// (``HyperliquidError``).
    ///
    /// `localizedDescription` explains the reason in a sentence, followed by ``message`` when there
    /// is one.
    public struct ClientError: Error, Sendable, CustomStringConvertible {
        public var reason: Reason
        /// Details for diagnostics, such as the text of Hyperliquid's stream error.
        public var message: String?

        public init(_ reason: Reason, message: String? = nil) {
            self.reason = reason
            self.message = message
        }

        public var description: String {
            guard let message, !message.isEmpty else { return "Hyperliquid client error: \(reason)" }
            return "Hyperliquid client error: \(reason): \(message)"
        }
    }
}

extension Hyperliquid.ClientError: LocalizedError {
    public var errorDescription: String? {
        guard let message, !message.isEmpty else { return reason.summary }
        return "\(reason.summary): \(message)"
    }
}

extension Hyperliquid.ClientError {
    /// What went wrong.
    public struct Reason: Hashable, Sendable, CustomStringConvertible {
        private let name: String
        fileprivate let summary: String

        private init(_ name: String, summary: String) {
            self.name = name
            self.summary = summary
        }

        public var description: String { name }

        // MARK: Input

        /// A string isn't an address: `0x` and 40 hexadecimal digits.
        public static let invalidAddress = Self("invalidAddress", summary: "The text isn't an address")
        /// A string isn't a client order ID: `0x` and 32 hexadecimal digits.
        public static let invalidClientOrderID = Self(
            "invalidClientOrderID", summary: "The text isn't a client order ID"
        )

        // MARK: Client setup

        /// An action was called on a client without a signer.
        public static let missingSigner = Self("missingSigner", summary: "The client has no signer for an action")
        /// An account read was called without an address, on a client without an account.
        public static let missingAccount = Self(
            "missingAccount", summary: "The request needs an account address and the client has none"
        )

        // MARK: Markets

        /// The coin isn't in Hyperliquid's list of markets for its perp DEX.
        public static let unknownCoin = Self("unknownCoin", summary: "Hyperliquid lists no market for the coin")
        /// The coin is a spot or outcome market, which the client can't trade.
        public static let unsupportedMarket = Self(
            "unsupportedMarket", summary: "The client trades only perpetuals"
        )
        /// A market order needs a mid price and the coin has none.
        public static let noMidPrice = Self("noMidPrice", summary: "The coin has no mid price for a market order")

        // MARK: Streams

        /// Hyperliquid refused a stream subscription, or closed the connection when it was sent.
        public static let subscriptionRejected = Self(
            "subscriptionRejected", summary: "Hyperliquid rejected the stream subscription"
        )
        /// Hyperliquid didn't acknowledge a stream request in time.
        public static let acknowledgementTimedOut = Self(
            "acknowledgementTimedOut", summary: "Hyperliquid didn't acknowledge the stream request in time"
        )
        /// The stream connection closed.
        public static let connectionClosed = Self("connectionClosed", summary: "The stream connection closed")
    }
}
