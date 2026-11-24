import AsyncHTTPClient
import Foundation
import HyperliquidKitCore
import NIOCore
import NIOHTTP1

/// Sends requests with AsyncHTTPClient, on every platform.
///
/// Network failures are thrown as `Hyperliquid.ClientError` with ``Hyperliquid/ClientError/Reason/timedOut``
/// or ``Hyperliquid/ClientError/Reason/connectionFailed``, so apps never see AsyncHTTPClient's or
/// SwiftNIO's error types. `CancellationError` passes through.
struct AsyncHTTPClientTransport: HTTPTransport {
    /// The largest response body read. `allPerpMetas`, among the largest responses, is about 90 KB.
    var maximumResponseSize = 32 * 1024 * 1024

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        var outgoing = HTTPClientRequest(url: request.url.absoluteString)
        outgoing.method = .POST
        outgoing.headers.add(name: "Content-Type", value: "application/json")
        outgoing.body = .bytes(request.body)
        do {
            // AsyncHTTPClient's deadline ends when the response head arrives, so the body gets the
            // time that is left.
            let deadline = request.timeout.map { ContinuousClock.now + $0 }
            // Without a deadline, a connection that can't be made must fail rather than be tried again
            // forever; with one, trying again for up to 10 seconds rides out a brief outage.
            let client: HTTPClient = request.timeout == nil ? .hyperliquidWithoutRetries : .hyperliquid
            let response = try await client.execute(
                outgoing, deadline: request.timeout.map { .now() + TimeAmount($0) } ?? .distantFuture
            )
            let body = try await withDeadline(deadline) { [maximumResponseSize] in
                try await response.body.collect(upTo: maximumResponseSize)
            }
            return TransportResponse(status: Int(response.status.code), body: Data(body.readableBytesView))
        } catch {
            // AsyncHTTPClient can fail a cancelled request with its own error first.
            if Task.isCancelled { throw CancellationError() }
            throw Self.clientError(for: error)
        }
    }

    /// The error apps see for an error AsyncHTTPClient or SwiftNIO threw.
    ///
    /// AsyncHTTPClient's timeouts become ``Hyperliquid/ClientError/Reason/timedOut``; every other
    /// failure becomes ``Hyperliquid/ClientError/Reason/connectionFailed``. Neither tells whether the
    /// request left the device.
    static func clientError(for error: any Error) -> any Error {
        switch error {
        case is CancellationError:
            error
        case let error as HTTPClientError where timeouts.contains(error):
            Hyperliquid.ClientError(.timedOut, underlyingError: error)
        case is NIOTooManyBytesError:
            Hyperliquid.ClientError(
                .connectionFailed, message: "The response is larger than the client reads", underlyingError: error
            )
        default:
            Hyperliquid.ClientError(.connectionFailed, underlyingError: error)
        }
    }

    private static let timeouts: [HTTPClientError] = [
        .deadlineExceeded, .connectTimeout, .readTimeout, .writeTimeout, .tlsHandshakeTimeout,
        .getConnectionFromPoolTimeout, .socksHandshakeTimeout, .httpProxyHandshakeTimeout,
    ]
}

/// Runs `operation`, or throws `HTTPClientError.deadlineExceeded` once `deadline` passes. Without a
/// deadline it just runs `operation`.
private func withDeadline<Result: Sendable>(
    _ deadline: ContinuousClock.Instant?, _ operation: @escaping @Sendable () async throws -> Result
) async throws -> Result {
    guard let deadline else { return try await operation() }
    return try await withThrowingTaskGroup(of: Result?.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(until: deadline, clock: .continuous)
            return nil
        }
        defer { group.cancelAll() }
        guard let result = try await group.next(), let result else {
            throw HTTPClientError.deadlineExceeded
        }
        return result
    }
}

extension HTTPClient {
    /// The client for requests with a timeout: the shared client's settings without a read timeout, so
    /// a request's only limit is the configured timeout. A connection that can't be made is tried again
    /// until that deadline or for 10 seconds, whichever comes first.
    static let hyperliquid = HTTPClient(retryingConnections: true)

    /// The client for requests without a timeout: a connection that can't be made fails within
    /// AsyncHTTPClient's 10-second connect limit, with every request waiting for it, instead of being
    /// tried again forever.
    static let hyperliquidWithoutRetries = HTTPClient(retryingConnections: false)

    private convenience init(retryingConnections: Bool) {
        var configuration = HTTPClient.Configuration.singletonConfiguration
        configuration.timeout = .init(connect: nil, read: nil)
        configuration.connectionPool.retryConnectionEstablishment = retryingConnections
        self.init(eventLoopGroup: HTTPClient.defaultEventLoopGroup, configuration: configuration)
    }
}
