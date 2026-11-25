import Foundation

/// Sends one HTTP request and returns the whole response.
///
/// The seam between the request flow and the network: ``AsyncHTTPClientTransport`` sends over the
/// network, and tests substitute a fake that records requests and replays responses.
protocol HTTPTransport: Sendable {
    func send(_ request: TransportRequest) async throws -> TransportResponse
}

/// A `POST` with a JSON body, which is every request Hyperliquid's REST API takes.
struct TransportRequest: Hashable, Sendable {
    var url: URL
    var body: Data
    /// How long the request may take, from sending to the last byte of the response; `nil` for no limit.
    var timeout: Duration?
}

struct TransportResponse: Hashable, Sendable {
    var status: Int
    var body: Data
}
