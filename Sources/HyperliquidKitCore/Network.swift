package import Foundation

extension Hyperliquid {
    /// A Hyperliquid network.
    ///
    /// Asset IDs differ between networks, and an account needs funds on each one it trades on.
    public struct Network: Hashable, Sendable, CustomStringConvertible {
        public let description: String
        package let apiURL: URL
        package let streamURL: URL
        /// The `source` an action's signature names.
        package let signatureSource: String
        /// The `hyperliquidChain` an action signed by an account's own wallet names.
        package let chainName: String

        // swift-format-ignore: NeverForceUnwrap
        // Fixed, valid URLs.
        public static let mainnet = Self(
            description: "mainnet",
            apiURL: URL(string: "https://api.hyperliquid.xyz")!,
            streamURL: URL(string: "wss://api.hyperliquid.xyz/ws")!,
            signatureSource: "a",
            chainName: "Mainnet"
        )

        // swift-format-ignore: NeverForceUnwrap
        // Fixed, valid URLs.
        public static let testnet = Self(
            description: "testnet",
            apiURL: URL(string: "https://api.hyperliquid-testnet.xyz")!,
            streamURL: URL(string: "wss://api.hyperliquid-testnet.xyz/ws")!,
            signatureSource: "b",
            chainName: "Testnet"
        )
    }
}
