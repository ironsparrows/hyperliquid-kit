import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Client")
    struct ClientTests {
        @Test func `the configuration's network and timeout reach every request`() async throws {
            let transport = FakeTransport(json: "[null]")
            let client = Hyperliquid.Client(configuration: .init(network: .testnet, timeout: .seconds(5)), transport: transport)
            _ = try await client.market.perpDexs()
            let request = try #require(await transport.requests.first)
            #expect(request.url.absoluteString == "https://api.hyperliquid-testnet.xyz/info")
            #expect(request.timeout == .seconds(5))
        }

        @Test func `by default a client reads mainnet with no timeout`() {
            let configuration = Hyperliquid.Client.Configuration()
            #expect(configuration.network == .mainnet)
            #expect(configuration.timeout == nil)
        }
    }
}
