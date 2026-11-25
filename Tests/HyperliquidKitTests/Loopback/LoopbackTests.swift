import Foundation
import Testing

@testable import HyperliquidKit

// Real HTTP to a local server, through the client's public API where it can be.
extension HyperliquidKitTests {
    @Suite("Loopback HTTP", .timeLimit(.minutes(1)))
    struct LoopbackTests {
        private func market(_ url: URL, timeout: Duration? = nil) -> any Hyperliquid.MarketAPI {
            let info = InfoClient(url: url.appending(path: "info"), transport: AsyncHTTPClientTransport(), timeout: timeout)
            return MarketEndpoints(info: info, directory: AssetDirectory(info: info))
        }

        @Test func `a read posts JSON and decodes the answer`() async throws {
            try await LoopbackServer.run(answering: .respond(status: 200, body: #"[null]"#)) { server in
                #expect(try await market(server.url).perpDexs().isEmpty)
                var requests = server.requests.makeAsyncIterator()
                let request = try #require(await requests.next())
                #expect(request.method == "POST")
                #expect(request.uri == "/info")
                #expect(request.headers["Content-Type"] == "application/json")
                #expect(request.body == #"{"type":"perpDexs"}"#)
            }
        }

        @Test func `a 500 with a null body throws its status`() async throws {
            try await LoopbackServer.run(answering: .respond(status: 500, body: "null")) { server in
                await #expect {
                    try await market(server.url).perpDexs()
                } throws: { error in
                    (error as? HyperliquidError)?.httpStatus == 500
                }
            }
        }

        @Test func `a closed connection throws connection failed`() async throws {
            try await LoopbackServer.run(answering: .close) { server in
                await #expect {
                    try await market(server.url).perpDexs()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .connectionFailed
                }
            }
        }

        @Test func `a server that never answers throws timed out after the timeout`() async throws {
            try await LoopbackServer.run(answering: .never) { server in
                await #expect {
                    try await market(server.url, timeout: .milliseconds(300)).perpDexs()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .timedOut
                }
            }
        }

        // Without a timeout, a connection that can't be made still fails, within the 10-second connect limit.
        @Test func `a refused connection throws connection failed, even without a timeout`() async throws {
            let url = try await LoopbackServer.unusedURL()
            await #expect {
                try await market(url, timeout: nil).perpDexs()
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .connectionFailed
            }
        }

        @Test func `a server that stops mid-body throws timed out after the timeout`() async throws {
            try await LoopbackServer.run(answering: .stallBody) { server in
                await #expect {
                    try await market(server.url, timeout: .milliseconds(300)).perpDexs()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .timedOut
                }
            }
        }
    }
}
