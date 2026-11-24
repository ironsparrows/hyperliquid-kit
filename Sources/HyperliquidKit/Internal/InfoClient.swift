import Foundation
import HyperliquidKitCore

/// Sends reads to Hyperliquid's `/info` endpoint.
struct InfoClient: Sendable {
    let url: URL
    let transport: any HTTPTransport
    let timeout: Duration?

    init(network: Hyperliquid.Network, transport: any HTTPTransport, timeout: Duration?) {
        self.init(url: network.apiURL.appending(path: "info"), transport: transport, timeout: timeout)
    }

    init(url: URL, transport: any HTTPTransport, timeout: Duration?) {
        self.url = url
        self.transport = transport
        self.timeout = timeout
    }

    /// Sends a read and decodes its response.
    func send<Response: Decodable & Sendable>(_ request: InfoRequest<Response>) async throws -> Response {
        // 1. Write the body: `{"type": …}` and the read's parameters.
        let body = Data(request.body.json.utf8)
        // 2. POST it as JSON.
        let response = try await transport.send(TransportRequest(url: url, body: body, timeout: timeout))
        // 3. A status of 400 or more is Hyperliquid's error, with its text.
        guard response.status < 400 else {
            throw HyperliquidError(
                .httpStatus, message: Self.message(in: response.body, status: response.status), httpStatus: response.status,
                body: response.body
            )
        }
        // 4. A `null` body is an error, unless the read's result is optional: Hyperliquid answers some
        //    reads it can't serve, such as `allMids` for an unknown perp DEX, with 200 and `null`.
        if !(Response.self is any OptionalResponse.Type), Self.isNull(response.body) {
            throw HyperliquidError(
                .unexpectedResponse, message: "Hyperliquid answered null", httpStatus: response.status,
                body: response.body
            )
        }
        // 5. Decode off the caller's actor: some responses are tens of kilobytes.
        return try await Self.decode(Response.self, from: response.body)
    }

    /// Whether the body is JSON `null`, allowing whitespace around it.
    private static func isNull(_ body: Data) -> Bool {
        body.count < 16 && String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }

    @concurrent
    private static func decode<Response: Decodable & Sendable>(_ type: Response.Type, from data: Data) async throws
        -> Response
    {
        try JSONDecoder().decode(type, from: data)
    }

    /// For a 4xx status, the `msg` of a JSON error body `{code, msg, data}`; otherwise, and when the
    /// body isn't one, the whole body as text. Hyperliquid answers most errors in plain text.
    private static func message(in body: Data, status: Int) -> String {
        struct ErrorBody: Decodable {
            let msg: String
        }
        if (400..<500).contains(status), let error = try? JSONDecoder().decode(ErrorBody.self, from: body) {
            return error.msg
        }
        return String(decoding: body, as: UTF8.self)
    }
}

/// Marks `Optional` responses, whose `null` decodes as `nil` instead of throwing.
private protocol OptionalResponse {}

extension Optional: OptionalResponse {}

/// One read: the body to send, and the type its response decodes to.
struct InfoRequest<Response: Decodable & Sendable>: Sendable {
    let body: ActionValue

    /// A read of `type` with its parameters, in the order they are written.
    init(_ type: String, _ parameters: [ActionValue.Entry] = []) {
        body = .map([.init(key: "type", value: .string(type))] + parameters)
    }
}
