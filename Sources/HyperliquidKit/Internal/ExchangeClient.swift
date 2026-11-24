import Foundation
import HyperliquidKitCore

/// Signs actions and sends them to Hyperliquid's `/exchange` endpoint.
struct ExchangeClient: Sendable {
    let url: URL
    let network: Hyperliquid.Network
    let transport: any HTTPTransport
    let timeout: Duration?
    let signer: (any Hyperliquid.Signer)?
    let vault: Hyperliquid.Address?
    let nonces: NonceSource

    /// The client's signer, or `missingSigner` when it has none. Actions call this before any read
    /// they need, so a client without a signer sends nothing.
    func requireSigner() throws(Hyperliquid.ClientError) -> any Hyperliquid.Signer {
        guard let signer else { throw Hyperliquid.ClientError(.missingSigner) }
        return signer
    }

    /// Sends an action on several orders and returns one status per order.
    ///
    /// When Hyperliquid rejects the whole batch before looking at single orders, it can answer with one
    /// status for all of them; that throws, since the statuses can't be matched to the orders.
    func perform<Status: Decodable & Sendable>(_ action: ActionValue, statusesFor count: Int, expiresAfter: Date?)
        async throws -> [Status]
    {
        let (statuses, answer) = try await perform(
            action, nonce: nil, expiresAfter: expiresAfter, decoding: StatusesResponse<Status>.self
        )
        let list = statuses?.statuses ?? []
        guard list.count == count else {
            throw HyperliquidError(
                .actionRejected, message: "\(list.count) statuses for \(count) orders: \(list)",
                httpStatus: answer.status, body: answer.body, nonce: answer.nonce
            )
        }
        return list
    }

    /// Sends an action on one item, such as a TWAP order, and returns its status.
    func perform<Status: Decodable & Sendable>(_ action: ActionValue, decoding _: Status.Type, expiresAfter: Date?)
        async throws -> Status
    {
        let (response, answer) = try await perform(
            action, nonce: nil, expiresAfter: expiresAfter, decoding: StatusResponse<Status>.self
        )
        guard let status = response?.status else {
            throw HyperliquidError(
                .unexpectedResponse, message: "The answer has no status", httpStatus: answer.status,
                body: answer.body, nonce: answer.nonce
            )
        }
        return status
    }

    /// Sends an action whose response the client doesn't read.
    ///
    /// - Parameter nonce: The nonce to sign with; `nil` takes the signer's next one.
    func perform(_ action: ActionValue, nonce: UInt64? = nil, expiresAfter: Date?) async throws {
        _ = try await perform(action, nonce: nonce, expiresAfter: expiresAfter, decoding: IgnoredResponse.self)
    }

    /// Signs and sends an action, and decodes the `response` of Hyperliquid's answer.
    ///
    /// Every error after the nonce is taken carries it: Hyperliquid's rejections, network failures and
    /// an answer the client can't read.
    private func perform<Response: Decodable & Sendable>(
        _ action: ActionValue, nonce: UInt64?, expiresAfter: Date?, decoding response: Response.Type
    ) async throws -> (Response?, Answer) {
        // 1. The signer, and the nonce it signs with.
        let signer = try requireSigner()
        let nonce = if let nonce { nonce } else { await nonces.next(for: signer.address, on: network) }
        let expiresAfter = expiresAfter.map(milliseconds)
        // 2. Sign the action with what Hyperliquid hashes beside it.
        let l1Action = L1Action(action: action, nonce: nonce, vault: vault, expiresAfter: expiresAfter)
        let signature = try await signer.sign(l1Action.signingRequest(on: network))
        // 3. POST the action as signed, with the signature, the vault and the expiry (`null` when unset).
        let body: ActionValue = [
            "action": action,
            "nonce": .unsigned(nonce),
            "signature": ["r": .string(signature.wireR), "s": .string(signature.wireS), "v": .unsigned(UInt64(signature.v))],
            "vaultAddress": vault.map { .string($0.description) } ?? .null,
            "expiresAfter": expiresAfter.map(ActionValue.unsigned) ?? .null,
        ]
        let response: TransportResponse
        do {
            response = try await transport.send(TransportRequest(url: url, body: Data(body.json.utf8), timeout: timeout))
        } catch var error as Hyperliquid.ClientError {
            error.nonce = nonce
            throw error
        }
        let answer = Answer(nonce: nonce, status: response.status, body: response.body)
        // 4. A status of 400 or more, or `"status": "err"`, is Hyperliquid's rejection.
        guard response.status < 400 else {
            throw HyperliquidError(
                .httpStatus, message: InfoClient.message(in: response.body, status: response.status),
                httpStatus: response.status, body: response.body, nonce: nonce
            )
        }
        let envelope: Envelope<Response>
        do {
            envelope = try JSONDecoder().decode(Envelope<Response>.self, from: response.body)
        } catch {
            throw HyperliquidError(
                .unexpectedResponse, message: "\(error)", httpStatus: response.status, body: response.body, nonce: nonce
            )
        }
        switch envelope {
        case .rejected(let message):
            throw HyperliquidError(.actionRejected, message: message, httpStatus: response.status, body: response.body, nonce: nonce)
        case .accepted(let decoded):
            return (decoded, answer)
        }
    }

    private struct Answer {
        let nonce: UInt64
        let status: Int
        let body: Data
    }
}

/// Milliseconds since 1970, zero for an earlier date.
func milliseconds(_ date: Date) -> UInt64 {
    UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
}

// MARK: - Wire

/// `{"status": "ok", "response": …}` or `{"status": "err", "response": "message"}`.
private enum Envelope<Response: Decodable>: Decodable {
    case accepted(Response?)
    case rejected(String)

    private enum CodingKeys: String, CodingKey {
        case status, response
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(String.self, forKey: .status) == "ok" {
            self = .accepted(try container.decodeIfPresent(Response.self, forKey: .response))
        } else {
            self = .rejected(try container.decode(String.self, forKey: .response))
        }
    }
}

/// `{"type": …, "data": {"statuses": [...]}}`, the response of an action on several orders.
struct StatusesResponse<Status: Decodable & Sendable>: Decodable, Sendable {
    let statuses: [Status]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    private struct Payload: Decodable {
        let statuses: [Status]
    }

    init(from decoder: any Decoder) throws {
        statuses = try decoder.container(keyedBy: CodingKeys.self).decode(Payload.self, forKey: .data).statuses
    }
}

/// `{"type": …, "data": {"status": …}}`, the response of an action on one item.
struct StatusResponse<Status: Decodable & Sendable>: Decodable, Sendable {
    let status: Status

    private enum CodingKeys: String, CodingKey {
        case data
    }

    private struct Payload: Decodable {
        let status: Status
    }

    init(from decoder: any Decoder) throws {
        status = try decoder.container(keyedBy: CodingKeys.self).decode(Payload.self, forKey: .data).status
    }
}

/// A response the client doesn't read, such as `{"type": "default"}`.
struct IgnoredResponse: Decodable, Sendable {
    init(from decoder: any Decoder) throws {}
}
