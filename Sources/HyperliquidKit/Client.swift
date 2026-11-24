public import HyperliquidKitCore

extension Hyperliquid {
    /// The client for Hyperliquid's perpetuals.
    ///
    /// Reads go through its domains, such as ``market``. A client is a reference that every holder
    /// shares.
    public final class Client: API {
        public let market: any MarketAPI

        /// Creates a client for the configuration's network.
        public convenience init(configuration: Configuration = .init()) {
            self.init(configuration: configuration, transport: AsyncHTTPClientTransport())
        }

        init(configuration: Configuration, transport: any HTTPTransport) {
            let info = InfoClient(network: configuration.network, transport: transport, timeout: configuration.timeout)
            market = MarketRequests(info: info)
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
