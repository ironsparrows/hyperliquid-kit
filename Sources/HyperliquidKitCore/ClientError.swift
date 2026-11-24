public import Foundation

extension Hyperliquid {
    /// A failure the client detected itself, as opposed to one Hyperliquid reported
    /// (``HyperliquidError``).
    ///
    /// Network failures, such as a timeout or no connection, arrive as this error too, with the
    /// network library's error in ``underlyingError``. Canceling the task throws `CancellationError`
    /// instead.
    ///
    /// `localizedDescription` explains the reason in a sentence, followed by ``message`` when there
    /// is one.
    public struct ClientError: Error, Sendable, CustomStringConvertible {
        public var reason: Reason
        /// Details for diagnostics, such as the text of Hyperliquid's stream error.
        public var message: String?
        /// The error that caused this one, such as the network library's error behind
        /// ``Reason/timedOut``.
        ///
        /// For diagnostics only: its type differs between platforms and library versions, so don't
        /// match on it.
        public var underlyingError: (any Error)?
        /// The nonce of the action that failed, when an action failed on the network.
        ///
        /// A timed-out or dropped action may still have reached Hyperliquid and may still execute.
        /// `order.invalidate(nonce:)` spends this nonce: if it reaches Hyperliquid first, the action can
        /// no longer execute, since Hyperliquid accepts each nonce once.
        public var nonce: UInt64?

        public init(
            _ reason: Reason, message: String? = nil, underlyingError: (any Error)? = nil, nonce: UInt64? = nil
        ) {
            self.reason = reason
            self.message = message
            self.underlyingError = underlyingError
            self.nonce = nonce
        }

        public var description: String {
            var text = "Hyperliquid client error: \(reason)"
            if let message, !message.isEmpty { text += ": \(message)" }
            if let underlyingError { text += " (\(underlyingError))" }
            return text
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

        /// The request can't be sent as built, such as a price with more decimals than an action can
        /// carry, or a stream that conflicts with one already streaming; ``Hyperliquid/ClientError/message``
        /// says which.
        public static let invalidRequest = Self("invalidRequest", summary: "The request can't be sent as built")

        // MARK: Signing

        /// A private key isn't 32 bytes, or 64 hexadecimal digits, of a valid secp256k1 key, or it
        /// couldn't sign.
        public static let invalidPrivateKey = Self(
            "invalidPrivateKey", summary: "The key isn't a usable secp256k1 private key"
        )
        /// A signature doesn't have a 32-byte `r` and `s` and a `v` of 27 or 28.
        public static let invalidSignature = Self(
            "invalidSignature", summary: "The signature doesn't have a 32-byte r and s and a v of 27 or 28"
        )

        // MARK: Client setup

        /// An action was called on a client without a signer.
        public static let missingSigner = Self("missingSigner", summary: "The client has no signer for an action")
        /// An account read was called without an address, on a client without an account.
        public static let missingAccount = Self(
            "missingAccount", summary: "The request needs an account address and the client has none"
        )

        // MARK: Markets

        /// The coin isn't in Hyperliquid's list of markets for its perp DEX, or the perp DEX isn't in its
        /// list of perp DEXs.
        public static let unknownCoin = Self(
            "unknownCoin", summary: "Hyperliquid lists no market for the coin, or no such perp DEX"
        )
        /// The coin is a spot or outcome market, which the client can't trade.
        public static let unsupportedMarket = Self(
            "unsupportedMarket", summary: "The client trades only perpetuals"
        )
        /// A market order needs a mid price and the coin has none.
        public static let noMidPrice = Self("noMidPrice", summary: "The coin has no mid price for a market order")

        // MARK: Streams

        /// The stream connection closed, or a stream message couldn't be sent on it.
        public static let connectionClosed = Self("connectionClosed", summary: "The stream connection closed")

        // MARK: Network

        /// Hyperliquid didn't answer in time: within the client's timeout, or the connection took more
        /// than 10 seconds.
        ///
        /// The request may still have reached Hyperliquid. Before repeating one that changes something,
        /// such as placing an order, check whether it took effect.
        public static let timedOut = Self("timedOut", summary: "Hyperliquid didn't answer in time")
        /// The client couldn't connect to Hyperliquid, or the connection failed before the whole
        /// response arrived.
        ///
        /// When the connection failed after the request was sent, the request may still have reached
        /// Hyperliquid. Before repeating one that changes something, such as placing an order, check
        /// whether it took effect.
        public static let connectionFailed = Self(
            "connectionFailed", summary: "The connection to Hyperliquid failed"
        )
    }
}
