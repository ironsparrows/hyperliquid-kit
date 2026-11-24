public import HyperliquidKitCore

extension Hyperliquid {
    /// The client for Hyperliquid's perpetuals.
    ///
    /// Reads go through its domains, such as ``market``. A client is a reference that every holder
    /// shares.
    public final class Client: API {
        public let market: any MarketAPI
        public let account: any AccountAPI
        public let position: any PositionAPI

        /// Creates a client for the configuration's network.
        ///
        /// - Parameter account: The account that account and position reads use when they are given
        ///   none. Pass the account's own address, not an API wallet's: an API wallet's address reads
        ///   as an empty account.
        public convenience init(account: Hyperliquid.Address? = nil, configuration: Configuration = .init()) {
            self.init(account: account, configuration: configuration, transport: AsyncHTTPClientTransport())
        }

        init(account: Hyperliquid.Address? = nil, configuration: Configuration, transport: any HTTPTransport) {
            let info = InfoClient(network: configuration.network, transport: transport, timeout: configuration.timeout)
            let directory = AssetDirectory(info: info)
            market = MarketRequests(info: info, directory: directory)
            self.account = AccountRequests(info: info, account: account)
            position = PositionRequests(info: info, directory: directory, account: account)
        }
    }
}

extension Hyperliquid.Client {
    /// Settings for a ``Hyperliquid/Client``.
    public struct Configuration: Sendable {
        /// Mainnet by default.
        public var network: Hyperliquid.Network
        /// How long a request may take, from sending it to the last byte of the response. `nil`, the
        /// default, sets no limit beyond 10 seconds to connect. A request that takes longer throws
        /// ``Hyperliquid/ClientError/Reason/timedOut``.
        public var timeout: Duration?

        public init(network: Hyperliquid.Network = .mainnet, timeout: Duration? = nil) {
            self.network = network
            self.timeout = timeout
        }
    }
}
