import Foundation
import Testing
@testable import HyperliquidKit

/// Records every request and answers each with the next scripted response.
actor FakeTransport: HTTPTransport {
    private(set) var requests: [TransportRequest] = []
    private var responses: [TransportResponse]

    init(responses: [TransportResponse] = []) {
        self.responses = responses
    }

    init(status: Int = 200, json: String) {
        self.init(responses: [TransportResponse(status: status, body: Data(json.utf8))])
    }

    /// The bodies sent, as text.
    var bodies: [String] {
        requests.map { String(decoding: $0.body, as: UTF8.self) }
    }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            Issue.record("No response scripted for \(String(decoding: request.body, as: UTF8.self))")
            throw CancellationError()
        }
        return responses.removeFirst()
    }
}

extension InfoClient {
    static func test(_ transport: some HTTPTransport, network: Hyperliquid.Network = .mainnet) -> InfoClient {
        InfoClient(network: network, transport: transport, timeout: nil)
    }
}
