import Foundation
import Testing
@testable import HyperliquidKit

/// Records every request and answers each with the next scripted response.
actor FakeTransport: HTTPTransport {
    private(set) var requests: [TransportRequest] = []
    private var responses: [TransportResponse]
    /// Answers each request by its body, instead of the scripted responses.
    private let answer: (@Sendable (String) -> TransportResponse)?

    init(responses: [TransportResponse] = []) {
        self.responses = responses
        answer = nil
    }

    init(answer: @escaping @Sendable (_ body: String) -> TransportResponse) {
        responses = []
        self.answer = answer
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
        if let answer { return answer(String(decoding: request.body, as: UTF8.self)) }
        guard !responses.isEmpty else {
            Issue.record("No response scripted for \(String(decoding: request.body, as: UTF8.self))")
            throw CancellationError()
        }
        return responses.removeFirst()
    }
}

extension TransportResponse {
    /// A 200 answer with this JSON body.
    static func json(_ text: String) -> Self {
        Self(status: 200, body: Data(text.utf8))
    }
}

extension InfoClient {
    static func test(_ transport: some HTTPTransport, network: Hyperliquid.Network = .mainnet) -> InfoClient {
        InfoClient(network: network, transport: transport, timeout: nil)
    }
}

extension ExchangeClient {
    /// A mainnet exchange client whose nonces start at `nonce`, with the Python SDK's test key as signer.
    static func test(
        _ transport: some HTTPTransport, signer: (any Hyperliquid.Signer)? = SigningFixtures.pythonTestSigner,
        nonce: UInt64 = 0, vault: Hyperliquid.Address? = nil
    ) -> ExchangeClient {
        ExchangeClient(
            url: Hyperliquid.Network.mainnet.apiURL.appending(path: "exchange"), network: .mainnet, transport: transport,
            timeout: nil, signer: signer, vault: vault, nonces: NonceSource { nonce }
        )
    }
}

extension OrderEndpoints {
    static func test(
        _ transport: some HTTPTransport, account: Hyperliquid.Address? = nil,
        signer: (any Hyperliquid.Signer)? = SigningFixtures.pythonTestSigner, nonce: UInt64 = 0,
        vault: Hyperliquid.Address? = nil
    ) -> OrderEndpoints {
        let info = InfoClient.test(transport)
        return OrderEndpoints(
            info: info,
            exchange: .test(transport, signer: signer, nonce: nonce, vault: vault),
            directory: AssetDirectory(info: info), account: account
        )
    }
}

extension PositionEndpoints {
    static func test(
        _ transport: some HTTPTransport, account: Hyperliquid.Address? = nil,
        signer: (any Hyperliquid.Signer)? = SigningFixtures.pythonTestSigner, nonce: UInt64 = 0
    ) -> PositionEndpoints {
        let info = InfoClient.test(transport)
        return PositionEndpoints(
            info: info, exchange: .test(transport, signer: signer, nonce: nonce), directory: AssetDirectory(info: info),
            account: account
        )
    }
}

extension TwapEndpoints {
    static func test(
        _ transport: some HTTPTransport, account: Hyperliquid.Address? = nil,
        signer: (any Hyperliquid.Signer)? = SigningFixtures.pythonTestSigner, nonce: UInt64 = 0
    ) -> TwapEndpoints {
        let info = InfoClient.test(transport)
        return TwapEndpoints(
            info: info, exchange: .test(transport, signer: signer, nonce: nonce), directory: AssetDirectory(info: info),
            account: account
        )
    }
}
