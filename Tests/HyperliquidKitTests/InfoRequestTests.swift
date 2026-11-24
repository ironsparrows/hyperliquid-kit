import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Info requests")
    struct InfoRequestTests {
        @Test(arguments: [(Hyperliquid.Network.mainnet, "https://api.hyperliquid.xyz/info"), (.testnet, "https://api.hyperliquid-testnet.xyz/info")])
        func `a read is a POST of its JSON body to the network's info endpoint`(network: Hyperliquid.Network, url: String) async throws {
            let transport = FakeTransport(json: #"{"universe":[],"marginTables":[]}"#)
            _ = try await InfoClient.test(transport, network: network).send(.meta(.named("xyz")))
            let request = try #require(await transport.requests.first)
            #expect(request.url.absoluteString == url)
            #expect(String(decoding: request.body, as: UTF8.self) == #"{"type":"meta","dex":"xyz"}"#)
            #expect(request.timeout == nil)
        }

        // Recorded: an unknown coin answers 500 with `null`, an unknown type 422 with plain text.
        @Test(arguments: [
            (500, "null", "null"),
            (422, "Failed to deserialize the JSON body into the target type", "Failed to deserialize the JSON body into the target type"),
            (400, #"{"code":1,"msg":"Bad request","data":null}"#, "Bad request"),
            (502, #"{"code":1,"msg":"Bad gateway","data":null}"#, #"{"code":1,"msg":"Bad gateway","data":null}"#),
        ])
        func `a status of 400 or more throws Hyperliquid's text with the status`(status: Int, body: String, message: String) async {
            let transport = FakeTransport(status: status, json: body)
            await #expect {
                try await InfoClient.test(transport).send(.perpDexs)
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.kind == .httpStatus && error.httpStatus == status && error.message == message
                    && error.body == Data(body.utf8)
            }
        }

        @Test func `a body that doesn't decode throws an unexpected response with the body`() async {
            await #expect {
                try await InfoClient.test(FakeTransport(json: "{}")).send(.perpDexs)
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.kind == .unexpectedResponse && error.body == Data("{}".utf8) && error.httpStatus == 200
            }
        }

        @Test func `a null body throws an unexpected response unless the result is optional`() async throws {
            await #expect {
                try await InfoClient.test(FakeTransport(json: " null\n")).send(.perpDexs)
            } throws: { error in
                (error as? HyperliquidError)?.kind == .unexpectedResponse
            }
            #expect(try await InfoClient.test(FakeTransport(json: "null")).send(.perpDexLimits(.first)) == nil)
        }
    }
}
