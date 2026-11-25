import Foundation
import HyperliquidKitCore
import NIOConcurrencyHelpers

/// The client's one WebSocket connection to Hyperliquid, shared by every stream.
///
/// It connects on the first subscription, pings every 50 seconds, sends a subscription when its first
/// stream arrives and an unsubscription when its last one leaves, and routes each push to the streams
/// of its topic. A closed connection ends every stream subscribed on it with `connectionClosed`;
/// nothing reconnects, and the next subscription, or a stream still being checked, opens a new
/// connection.
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
        /// Why a request that differs from the one already streaming on the topic is refused, when
        /// "other parameters" doesn't say it.
        var conflict: String? = nil
        /// Whether the pushes build on the snapshot Hyperliquid sends when subscribing, such as order
        /// book diffs. Only the stream that subscribed gets that snapshot, so a second stream of the
        /// topic is refused while the first one lasts.
        var buildsOnSnapshot = false
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
    /// Checks coins and perp DEXs before subscribing, and names the positions of positional pushes.
    let directory: AssetDirectory
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
    /// Streams that have ended, recorded at once, before their removal reaches the actor: a new
    /// subscription that conflicts only with ended streams removes them first.
    private let terminated = NIOLockedValueBox<Set<UUID>>([])

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

    /// How a stream keeps pushes its reader hasn't taken yet.
    enum Buffering: Sendable {
        /// Only the latest push: for state that each push replaces, such as a book.
        case latest
        /// Every push, in order: for events, such as trades.
        case all
    }

    /// What the connection hands a stream: a push to decode, or the stream's end.
    private enum Delivery: Sendable {
        case push(Data)
        case end((any Error)?)
    }

    /// A stream of the pushes of `subscription`, each decoded by `decode` off the connection's actor, in
    /// the order they arrived.
    ///
    /// The subscription is sent when the stream is created; ending the stream, by canceling its task or
    /// dropping it, removes it. A push that fails to decode ends the stream with the decoding error; a
    /// latest-only stream can skip a push before decoding it, when a newer one arrives first.
    nonisolated func stream<Element: Sendable>(
        _ subscription: Subscription, buffering: Buffering, decode: @escaping @Sendable (Data) throws -> Element
    ) -> AsyncThrowingStream<Element, any Error> {
        stream(subscription, buffering: buffering, decodeEach: { [try decode($0)] })
    }

    /// A stream of the elements each push of `subscription` holds, as `decodeEach` reads them.
    nonisolated func stream<Element: Sendable>(
        _ subscription: Subscription, buffering: Buffering, decodeEach: @escaping @Sendable (Data) throws -> [Element]
    ) -> AsyncThrowingStream<Element, any Error> {
        let latestOnly = buffering == .latest
        return stream(subscription, keepingEveryPush: !latestOnly, keepingEveryElement: !latestOnly, initial: ()) {
            _, data in try decodeEach(data)
        }
    }

    /// A stream of a state that every push of `subscription` changes, such as a book built from
    /// diffs: `merge` folds each push, in order, into the state that starts at `initial`, and returns
    /// what to yield. Every push is merged; a slow reader gets only the latest element.
    nonisolated func stream<State: Sendable, Element: Sendable>(
        _ subscription: Subscription, initial: State,
        merge: @escaping @Sendable (inout State, Data) throws -> [Element]
    ) -> AsyncThrowingStream<Element, any Error> {
        stream(subscription, keepingEveryPush: true, keepingEveryElement: false, initial: initial, reduce: merge)
    }

    private nonisolated func stream<State: Sendable, Element: Sendable>(
        _ subscription: Subscription, keepingEveryPush: Bool, keepingEveryElement: Bool, initial: State,
        reduce: @escaping @Sendable (inout State, Data) throws -> [Element]
    ) -> AsyncThrowingStream<Element, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: Element.self, bufferingPolicy: keepingEveryElement ? .unbounded : .bufferingNewest(1)
        )
        // Pushes queue here, then a task of the stream's own decodes them; a latest-only stream keeps only
        // the newest, and its end replaces whatever is queued.
        let (deliveries, delivery) = AsyncStream.makeStream(
            of: Delivery.self, bufferingPolicy: keepingEveryPush ? .unbounded : .bufferingNewest(1)
        )
        let decoder = Task {
            var state = initial
            for await item in deliveries {
                switch item {
                case .push(let data):
                    do {
                        for element in try reduce(&state, data) { continuation.yield(element) }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                case .end(let error):
                    continuation.finish(throwing: error)
                    return
                }
            }
        }
        let id = UUID()
        let created = generation.withLockedValue { $0 }
        let consumer = Consumer(
            topic: subscription.topic,
            deliver: { data in delivery.yield(.push(data)) },
            finish: { error in
                delivery.yield(.end(error))
                delivery.finish()
            }
        )
        continuation.onTermination = { [weak self] _ in
            self?.terminated.withLockedValue { _ = $0.insert(id) }
            decoder.cancel()
            delivery.finish()
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
            var session = try await openSession()
            guard consumers[id] != nil else { return }
            let topic = subscription.topic
            if requests[topic] != nil {
                // Streams that ended but whose removal is still on its way don't hold the topic: a stream
                // that replaces one subscribes afresh and gets its own snapshot.
                if let unsubscribe = purgeTerminated(topic) {
                    let sentOn = connection?.id
                    try? await session.send(unsubscribe)
                    guard consumers[id] != nil else { return }
                    // The connection may have closed meanwhile: subscribe on its replacement.
                    if connection?.id != sentOn { session = try await openSession() }
                }
                guard consumers[id] != nil else { return }
            }
            if let streaming = requests[topic], streaming != subscription.request {
                // Pushes don't say which parameters they were sent for, so two variants can't share a topic.
                throw Hyperliquid.ClientError(
                    .invalidRequest,
                    message: subscription.conflict
                        ?? "\(topic.channel) for \(topic.key) is already streaming with other parameters"
                )
            }
            if requests[topic] != nil, subscription.buildsOnSnapshot {
                let streaming = topic.key.isEmpty ? topic.channel : "\(topic.channel) for \(topic.key)"
                throw Hyperliquid.ClientError(
                    .invalidRequest,
                    message: "\(streaming) is already streaming: its pushes build on the snapshot that only the "
                        + "first stream gets, so it streams to one reader at a time"
                )
            }
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
        terminated.withLockedValue { _ = $0.remove(id) }
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

    /// Removes the topic's streams that have already ended, ahead of their own removal, and returns the
    /// unsubscription to send when that leaves the topic without streams.
    private func purgeTerminated(_ topic: Topic) -> String? {
        let ended = terminated.withLockedValue { $0 }
        for id in subscribers[topic] ?? [] where ended.contains(id) {
            consumers[id] = nil
            // Its removal, still to arrive, is then ignored.
            finishing.insert(id)
            if leave(id, topic: topic), let request = requests.removeValue(forKey: topic) {
                return Self.message("unsubscribe", request)
            }
        }
        return nil
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
                    guard let routed = await StreamRouter.route(frame) else { continue }
                    guard let self else { return }
                    await self.receive(routed.push, for: routed.destination, on: id)
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

    /// The connection ended without `disconnect()`: every stream subscribed on it ends with
    /// `connectionClosed`. Streams still being checked go on, and open a new connection.
    private func closed(_ id: UInt64) {
        guard let current = connection, current.id == id else { return }
        connection = nil
        current.pinger.cancel()
        let subscribed = Set(subscribers.values.joined())
        subscribers = [:]
        requests = [:]
        for id in subscribed {
            guard let consumer = consumers.removeValue(forKey: id) else { continue }
            finish(consumer, id, throwing: Hyperliquid.ClientError(.connectionClosed))
        }
    }

    // MARK: Receiving

    /// The `data` of a push `{"channel": …, "data": …}`.
    static func payload<Payload: Decodable>(_ type: Payload.Type, of data: Data) throws -> Payload {
        try JSONDecoder().decode(Push<Payload>.self, from: data).data
    }

    private func receive(_ data: Data, for destination: StreamRouter.Destination, on id: UInt64) {
        guard connection?.id == id else { return }
        let topics = switch destination {
        case .topic(let topic): [topic]
        case .channel(let channel): subscribers.keys.filter { $0.channel == channel }
        }
        for topic in topics {
            for id in subscribers[topic] ?? [] { consumers[id]?.deliver(data) }
        }
    }

    // MARK: Inspecting

    /// How many streams and subscriptions the connection tracks, for tests.
    var bookkeeping: (consumers: Int, subscribedTopics: Int, requests: Int, ended: Int, finishing: Int) {
        (consumers.count, subscribers.count, requests.count, ended.count, finishing.count)
    }

    // MARK: Wire

    /// `{"channel": …, "data": …}`.
    private struct Push<Payload: Decodable>: Decodable {
        let data: Payload
    }

    /// `{"method": …, "subscription": …}`.
    private static func message(_ method: String, _ subscription: ActionValue) -> String {
        ActionValue.map([.init(key: "method", value: .string(method)), .init(key: "subscription", value: subscription)]).json
    }
}
