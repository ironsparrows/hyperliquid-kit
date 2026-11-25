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

        @Test func `reads given no account use the signer's address`() async throws {
            let transport = FakeTransport(json: "[]")
            let client = Hyperliquid.Client(signer: SigningVectors.pythonTestSigner, configuration: .init(), transport: transport)
            _ = try await client.order.pending()
            #expect(await transport.bodies.first?.contains(#""user":"0x14791697260e4c9a71f18484c9f997b308e59325""#) == true)
        }

        @Test func `an account given to the client wins over the signer's address`() async throws {
            let transport = FakeTransport(json: "[]")
            let client = Hyperliquid.Client(
                account: "0x0000000000000000000000000000000000000001", signer: SigningVectors.pythonTestSigner,
                configuration: .init(), transport: transport
            )
            _ = try await client.order.pending()
            #expect(await transport.bodies.first?.contains(#""user":"0x0000000000000000000000000000000000000001""#) == true)
        }

        @Test func `with a vault, reads given no account use the vault's address`() async throws {
            let transport = FakeTransport(json: "[]")
            let vault: Hyperliquid.Address = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"
            let client = Hyperliquid.Client(
                account: "0x0000000000000000000000000000000000000001", signer: SigningVectors.pythonTestSigner,
                configuration: .init(vaultAddress: vault), transport: transport
            )
            _ = try await client.order.pending()
            #expect(await transport.bodies.first?.contains(#""user":"0x1719884eb866cb12b2287399b15f7db5e7d775ea""#) == true)
        }

        @Test func `by default a client reads mainnet with no timeout`() {
            let configuration = Hyperliquid.Client.Configuration()
            #expect(configuration.network == .mainnet)
            #expect(configuration.timeout == nil)
        }
    }
}
