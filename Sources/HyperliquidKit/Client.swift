import Foundation
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
        public let order: any OrderAPI
        public let twap: any TwapAPI
        public let stream: any StreamAPI
        private let connection: StreamConnection

        /// Creates a client for the configuration's network.
        ///
        /// - Parameters:
        ///   - account: The account that account, position, order and TWAP reads and account streams use
        ///     when they are given none. Pass the account's own address, not an API wallet's: an API
        ///     wallet's address reads as an empty account. Defaults to the signer's address; a
        ///     ``Configuration/vaultAddress`` replaces it, even when given.
        ///   - signer: Signs actions: the account's own key, or an API wallet's. Without one, actions throw
        ///     ``ClientError/Reason/missingSigner``.
        ///   - configuration: The network, the request timeout and the vault actions trade for.
        ///
        /// With ``Configuration/vaultAddress`` set, reads and streams given no account use the vault's
        /// address.
        public convenience init(
            account: Hyperliquid.Address? = nil, signer: (any Hyperliquid.Signer)? = nil, configuration: Configuration = .init()
        ) {
            self.init(
                account: account, signer: signer, configuration: configuration, transport: AsyncHTTPClientTransport(),
                webSocketTransport: WebSocketKitTransport()
            )
        }

        init(
            account: Hyperliquid.Address? = nil, signer: (any Hyperliquid.Signer)? = nil, configuration: Configuration,
            transport: any HTTPTransport, webSocketTransport: any WebSocketTransport = WebSocketKitTransport(),
            nonces: NonceSource = .shared
        ) {
            let info = InfoClient(network: configuration.network, transport: transport, timeout: configuration.timeout)
            let exchange = ExchangeClient(
                url: configuration.network.apiURL.appending(path: "exchange"), network: configuration.network,
                transport: transport, timeout: configuration.timeout, signer: signer,
                vault: configuration.vaultAddress, nonces: nonces
            )
            let directory = AssetDirectory(info: info)
            let account = configuration.vaultAddress ?? account ?? signer?.address
            market = MarketRequests(info: info, directory: directory)
            self.account = AccountRequests(info: info, account: account)
            position = PositionRequests(info: info, exchange: exchange, directory: directory, account: account)
            order = OrderRequests(info: info, exchange: exchange, directory: directory, account: account)
            twap = TwapRequests(info: info, exchange: exchange, directory: directory, account: account)
            connection = StreamConnection(
                url: configuration.network.streamURL, transport: webSocketTransport, directory: directory
            )
            stream = Streams(connection: connection, account: account)
        }

        /// Closes the stream connection.
        deinit {
            Task { [connection] in await connection.disconnect() }
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
        /// The sub-account or vault that actions trade for. The signer must be its owner's key or one of
        /// the owner's API wallets.
        public var vaultAddress: Hyperliquid.Address?

        public init(
            network: Hyperliquid.Network = .mainnet, timeout: Duration? = nil, vaultAddress: Hyperliquid.Address? = nil
        ) {
            self.network = network
            self.timeout = timeout
            self.vaultAddress = vaultAddress
        }
    }
}
