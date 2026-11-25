import AsyncHTTPClient
import NIOCore
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Transport errors")
    struct TransportErrorTests {
        @Test(arguments: [
            HTTPClientError.deadlineExceeded, .connectTimeout, .readTimeout, .getConnectionFromPoolTimeout,
        ])
        func `AsyncHTTPClient's timeouts become timed out`(error: HTTPClientError) {
            let mapped = AsyncHTTPClientTransport.clientError(for: error) as? Hyperliquid.ClientError
            #expect(mapped?.reason == .timedOut)
            #expect(mapped?.underlyingError is HTTPClientError)
        }

        @Test func `other failures become connection failed`() {
            let mapped = AsyncHTTPClientTransport.clientError(for: HTTPClientError.remoteConnectionClosed)
            #expect((mapped as? Hyperliquid.ClientError)?.reason == .connectionFailed)
            #expect(((AsyncHTTPClientTransport.clientError(for: NIOTooManyBytesError(maxBytes: 1))) as? Hyperliquid.ClientError)?.reason == .connectionFailed)
        }

        @Test func `cancellation passes through`() {
            #expect(AsyncHTTPClientTransport.clientError(for: CancellationError()) is CancellationError)
        }
    }
}
