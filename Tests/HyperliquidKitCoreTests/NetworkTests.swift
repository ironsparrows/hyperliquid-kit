import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Network")
    struct NetworkTests {
        @Test(arguments: [
            (Hyperliquid.Network.mainnet, "https://api.hyperliquid.xyz", "wss://api.hyperliquid.xyz/ws", "a", "Mainnet"),
            (.testnet, "https://api.hyperliquid-testnet.xyz", "wss://api.hyperliquid-testnet.xyz/ws", "b", "Testnet"),
        ])
        func `each network has its endpoints and signing names`(
            network: Hyperliquid.Network, api: String, stream: String, source: String, chain: String
        ) {
            #expect(network.apiURL.absoluteString == api)
            #expect(network.streamURL.absoluteString == stream)
            #expect(network.signatureSource == source)
            #expect(network.chainName == chain)
        }
    }
}
