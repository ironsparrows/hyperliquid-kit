import Foundation
import HyperliquidKitCore
import NIOConcurrencyHelpers

/// The client's one WebSocket connection to Hyperliquid, shared by every stream.
///
/// It connects on the first subscription, pings every 50 seconds, sends a subscription when its first
/// stream arrives and an unsubscription when its last one leaves, and routes each push to the streams
/// of its topic. A closed connection ends every stream with `connectionClosed`; nothing reconnects,
/// and the next subscription opens a new connection.
actor StreamConnection {
    /// What a push is about: its channel and the field that tells its subscriptions apart, such as
    /// `allMids` and the perp DEX.
    struct Topic: Hashable, Sendable {
        let channel: String
        let key: String
    }

    /// A subscription to send, the topic its pushes arrive on, and what to check before sending.
    struct Subscription: Sendable {
        let topic: Topic
        /// The `subscription` object of the `subscribe` and `unsubscribe` messages.
        let request: ActionValue
        /// A coin or perp DEX checked against Hyperliquid's lists before sending: Hyperliquid drops the
        /// whole connection when a subscription names a coin it doesn't know.
        var coin: Hyperliquid.Coin? = nil
        var dex: Hyperliquid.PerpDex? = nil
    }

    /// One stream's end of a subscription.
    private struct Consumer {
        let topic: Topic
        let deliver: @Sendable (Data) -> Void
        let finish: @Sendable ((any Error)?) -> Void
    }

    private struct Connection {
        let id: UInt64
        let session: any WebSocketSession
        let receiver: Task<Void, Never>
        let pinger: Task<Void, Never>
    }

    private let url: URL
    private let transport: any WebSocketTransport
    private let directory: AssetDirectory
    private let pingInterval: Duration

    private var connection: Connection?
    private var connecting: (id: UInt64, task: Task<any WebSocketSession, any Error>)?
    private var nextConnectionID: UInt64 = 0
    private var consumers: [UUID: Consumer] = [:]
    /// The streams of each topic whose subscription was sent.
    private var subscribers: [Topic: Set<UUID>] = [:]
    /// The request of each subscribed topic, for its unsubscription.
    private var requests: [Topic: ActionValue] = [:]
    /// Streams that ended before their subscription was added: the add is skipped.
    private var ended: Set<UUID> = []
    /// Streams the connection ended itself, whose own end is still to arrive.
    private var finishing: Set<UUID> = []
    /// Bumped by every ``disconnect()``: a stream created before one doesn't subscribe after it.
    private let generation = NIOLockedValueBox<UInt64>(0)

    init(url: URL, transport: any WebSocketTransport, directory: AssetDirectory, pingInterval: Duration = .seconds(50)) {
        self.url = url
        self.transport = transport
        self.directory = directory
        self.pingInterval = pingInterval
    }

    /// A connection released without ``disconnect()`` closes, and its streams end with
    /// `connectionClosed` instead of waiting forever.
    deinit {
        if let connection {
            connection.pinger.cancel()
            connection.receiver.cancel()
            Task { [session = connection.session] in await session.close() }
        }
        for consumer in consumers.values { consumer.finish(Hyperliquid.ClientError(.connectionClosed)) }
    }

    // MARK: Streams

    /// A stream of the pushes of `subscription`, each decoded by `decode`.
    ///
    /// The subscription is sent when the stream is created; ending the stream, by cancelling its task or
    /// dropping it, removes it. A push that doesn't decode ends the stream with the decoding error.
    nonisolated func stream<Element: Sendable>(
        _ subscription: Subscription, bufferingPolicy: AsyncThrowingStream<Element, any Error>.Continuation.BufferingPolicy,
        decode: @escaping @Sendable (Data) throws -> Element
    ) -> AsyncThrowingStream<Element, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
        let id = UUID()
        let created = generation.withLockedValue { $0 }
        let consumer = Consumer(
            topic: subscription.topic,
            deliver: { data in
                do {
                    continuation.yield(try decode(data))
                } catch {
                    continuation.finish(throwing: error)
                }
            },
            finish: { error in continuation.finish(throwing: error) }
        )
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        Task { await self.add(id, subscription, consumer, generation: created) }
        return stream
    }

    /// Closes the connection and ends every stream without an error.
    func disconnect() async {
        generation.withLockedValue { $0 += 1 }
        let current = connection
        connection = nil
        // A connection still opening is closed by the subscription waiting for it.
        connecting = nil
        current?.pinger.cancel()
        current?.receiver.cancel()
        finishAll(throwing: nil)
        await current?.session.close()
    }

    // MARK: Subscribing

    private func add(_ id: UUID, _ subscription: Subscription, _ consumer: Consumer, generation created: UInt64) async {
        if ended.remove(id) != nil { return }
        guard created == generation.withLockedValue({ $0 }) else {
            finish(consumer, id, throwing: nil)
            return
        }
        consumers[id] = consumer
        do {
            if let coin = subscription.coin { _ = try await directory.asset(for: coin) }
            if let dex = subscription.dex { try await directory.check(dex) }
            // The stream may have ended, or the connection been closed, during the checks.
            guard consumers[id] != nil else { return }
            let session = try await openSession()
            guard consumers[id] != nil else { return }
            let topic = subscription.topic
            let isFirst = subscribers[topic, default: []].isEmpty
            subscribers[topic, default: []].insert(id)
            if isFirst {
                requests[topic] = subscription.request
                try await session.send(Self.message("subscribe", subscription.request))
            }
        } catch {
            guard let consumer = consumers.removeValue(forKey: id) else { return }
            if leave(id, topic: subscription.topic) { requests[subscription.topic] = nil }
            finish(consumer, id, throwing: error)
        }
    }

    private func remove(_ id: UUID) async {
        if finishing.remove(id) != nil { return }
        guard let consumer = consumers.removeValue(forKey: id) else {
            ended.insert(id)
            return
        }
        guard leave(id, topic: consumer.topic), let request = requests.removeValue(forKey: consumer.topic),
            let session = connection?.session
        else { return }
        try? await session.send(Self.message("unsubscribe", request))
    }

    /// Removes the stream from its topic, and returns whether it was the topic's last.
    @discardableResult
    private func leave(_ id: UUID, topic: Topic) -> Bool {
        guard var ids = subscribers[topic], ids.remove(id) != nil else { return false }
        if ids.isEmpty {
            subscribers[topic] = nil
            return true
        }
        subscribers[topic] = ids
        return false
    }

    /// Ends a stream from the connection's side; its own end, which follows, is then ignored.
    private func finish(_ consumer: Consumer, _ id: UUID, throwing error: (any Error)?) {
        finishing.insert(id)
        consumer.finish(error)
    }

    private func finishAll(throwing error: (any Error)?) {
        let ending = consumers
        consumers = [:]
        subscribers = [:]
        requests = [:]
        for (id, consumer) in ending { finish(consumer, id, throwing: error) }
    }

    // MARK: Connection

    /// The open connection, opening it first when there is none. Concurrent callers share one attempt;
    /// a failed attempt is forgotten, so the next caller tries again.
    private func openSession() async throws -> any WebSocketSession {
        if let connection { return connection.session }
        let attempt: (id: UInt64, task: Task<any WebSocketSession, any Error>)
        if let connecting {
            attempt = connecting
        } else {
            nextConnectionID += 1
            attempt = (nextConnectionID, Task { [transport, url] in try await transport.connect(to: url) })
            connecting = attempt
        }
        let session: any WebSocketSession
        do {
            session = try await attempt.task.value
        } catch {
            if connecting?.id == attempt.id { connecting = nil }
            throw error
        }
        if let connection, connection.id == attempt.id { return connection.session }
        guard connecting?.id == attempt.id else {
            // Disconnected while connecting.
            await session.close()
            throw Hyperliquid.ClientError(.connectionClosed)
        }
        connecting = nil
        let id = attempt.id
        connection = Connection(
            id: id, session: session,
            receiver: Task { [weak self] in
                for await frame in session.frames {
                    guard let self else { return }
                    await self.receive(frame, on: id)
                }
                await self?.closed(id)
            },
            pinger: Task { [weak self, pingInterval] in
                while (try? await Task.sleep(for: pingInterval)) != nil {
                    guard let self else { return }
                    await self.ping(id)
                }
            }
        )
        return session
    }

    private func ping(_ id: UInt64) async {
        guard let connection, connection.id == id else { return }
        try? await connection.session.send(#"{"method":"ping"}"#)
    }

    /// The connection ended without `disconnect()`: every stream on it ends with `connectionClosed`.
    private func closed(_ id: UInt64) {
        guard let current = connection, current.id == id else { return }
        connection = nil
        current.pinger.cancel()
        finishAll(throwing: Hyperliquid.ClientError(.connectionClosed))
    }

    // MARK: Receiving

    private func receive(_ frame: String, on id: UInt64) {
        guard connection?.id == id else { return }
        let data = Data(frame.utf8)
        guard let topic = Self.topic(of: data), let ids = subscribers[topic] else { return }
        for id in ids { consumers[id]?.deliver(data) }
    }

    /// The topic of a push, or `nil` for a frame no stream reads: a pong, an error, a channel the client
    /// doesn't route, or text that isn't JSON.
    static func topic(of frame: Data) -> Topic? {
        struct Header: Decodable {
            let channel: String
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: frame) else { return nil }
        switch header.channel {
        case "allMids":
            // A push from the first perp DEX carries no `dex`.
            struct Push: Decodable {
                struct Mids: Decodable {
                    let dex: String?
                }
                let data: Mids
            }
            guard let push = try? JSONDecoder().decode(Push.self, from: frame) else { return nil }
            return Topic(channel: "allMids", key: push.data.dex ?? "")
        default:
            return nil
        }
    }

    // MARK: Inspecting

    /// How many streams and subscriptions the connection tracks, for tests.
    var bookkeeping: (consumers: Int, subscribedTopics: Int, requests: Int, ended: Int, finishing: Int) {
        (consumers.count, subscribers.count, requests.count, ended.count, finishing.count)
    }

    // MARK: Wire

    /// `{"method": …, "subscription": …}`.
    private static func message(_ method: String, _ subscription: ActionValue) -> String {
        ActionValue.map([.init(key: "method", value: .string(method)), .init(key: "subscription", value: subscription)]).json
    }
}
