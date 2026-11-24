import Foundation
import HyperliquidKitCore

/// How a push finds its streams: its channel and the field that tells its subscriptions apart, read
/// from the push alone.
extension StreamConnection {
    /// Where the frame goes and the push its streams read, worked out off the connection's actor, or
    /// `nil` for a frame no stream reads.
    @concurrent
    static func route(_ frame: String) async -> (destination: Destination, push: Data)? {
        routed(Data(frame.utf8))
    }

    /// The topic of a push, from the push alone, or `nil` for a frame no stream reads or one bound for
    /// every topic of its channel.
    static func topic(of frame: Data) -> Topic? {
        guard case .topic(let topic) = routed(frame)?.destination else { return nil }
        return topic
    }

    /// Where a push goes, from the push alone, and the push its streams read: the frame itself, or for
    /// a compressed order book diff `{"data": {"u": …}}` holding the inflated diff, which routing had
    /// to inflate to read its coin. `nil` for a frame no stream reads: a pong, an error, an
    /// acknowledgement, a channel the client doesn't route, an empty trades push, or text that isn't
    /// JSON.
    ///
    /// Account pushes are keyed by their lower-cased `user`, except order updates, events (channel
    /// `user`) and notifications, which carry none and share one topic per channel. Order book diffs
    /// (`l2`) are keyed by the coin inside them; one that doesn't inflate goes to every `l2` stream,
    /// which then ends with the error. `fastAssetCtxs` and `pac` go to their one stream, which
    /// inflates them.
    static func routed(_ frame: Data) -> (destination: Destination, push: Data)? {
        guard let push = try? JSONDecoder().decode(RoutingPush.self, from: frame) else { return nil }
        switch push.channel {
        case "fastAssetCtxs", "pac":
            return (.topic(Topic(channel: push.channel, key: "")), frame)
        case "l2":
            return push.bookUpdate.flatMap { routedBookUpdate($0, frame: frame) }
        default:
            return push.data.flatMap { topic(channel: push.channel, fields: $0) }.map { (.topic($0), frame) }
        }
    }

    /// An `l2` push: a snapshot or plain diff as it came, or a compressed diff inflated into `{"u": …}`.
    private static func routedBookUpdate(_ update: RoutingPush.BookUpdate, frame: Data)
        -> (destination: Destination, push: Data)?
    {
        if let coin = update.snapshotCoin ?? update.diffCoin {
            return (.topic(Topic(channel: "l2", key: coin)), frame)
        }
        // A push of another shape is dropped, as frames that route nowhere are.
        guard let text = update.compressed else { return nil }
        guard let json = inflated(base64: text),
            let diff = try? JSONDecoder().decode(RoutingPush.DiffCoin.self, from: json)
        else { return (.channel("l2"), frame) }
        let push = Data(#"{"data":{"u":"#.utf8) + json + Data("}}".utf8)
        return (.topic(Topic(channel: "l2", key: diff.c)), push)
    }

    /// The topic of a push on a channel routed by plain fields of its data.
    private static func topic(channel: String, fields: RoutingPush.Fields) -> Topic? {
        let user = fields.user?.lowercased()
        switch channel {
        case "allMids":
            // A push from the first perp DEX carries no `dex`.
            return Topic(channel: channel, key: fields.dex ?? "")
        case "l2Book", "bbo", "trades", "activeAssetCtx":
            return fields.coin.map { Topic(channel: channel, key: $0) }
        case "candle":
            guard let coin = fields.s, let interval = fields.i else { return nil }
            return Topic(channel: channel, key: "\(coin),\(interval)")
        case "orderUpdates", "user", "notification":
            return Topic(channel: channel, key: "")
        case "userFills", "userFundings", "userNonFundingLedgerUpdates", "userTwapSliceFills", "userTwapHistory",
            "spotState":
            return user.map { Topic(channel: channel, key: $0) }
        case "clearinghouseState", "openOrders", "twapStates":
            guard let user, let dex = fields.dex else { return nil }
            return Topic(channel: channel, key: "\(user),\(dex)")
        case "activeAssetData":
            guard let coin = fields.coin, let user else { return nil }
            return Topic(channel: channel, key: "\(coin),\(user)")
        default:
            return nil
        }
    }

    // MARK: Wire

    /// The fields a push is routed by: `{"channel": …, "data": …}`, where `data` is an object or, for
    /// trades, order updates and a candle array, a list whose first item carries them.
    private struct RoutingPush: Decodable {
        struct Fields: Decodable {
            let coin: String?
            let dex: String?
            let user: String?
            let s: String?
            let i: String?

            init(from decoder: any Decoder) throws {
                if var list = try? decoder.unkeyedContainer() {
                    guard !list.isAtEnd else {
                        (coin, dex, user, s, i) = (nil, nil, nil, nil, nil)
                        return
                    }
                    self = try list.decode(Fields.self)
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                coin = try? container.decodeIfPresent(String.self, forKey: .coin)
                dex = try? container.decodeIfPresent(String.self, forKey: .dex)
                user = try? container.decodeIfPresent(String.self, forKey: .user)
                s = try? container.decodeIfPresent(String.self, forKey: .s)
                i = try? container.decodeIfPresent(String.self, forKey: .i)
            }

            private enum CodingKeys: String, CodingKey {
                case coin, dex, user, s, i
            }
        }

        /// `l2` data: `{"s": book}`, `{"u": diff}` or `{"c": compressed diff}`.
        struct BookUpdate: Decodable {
            let snapshotCoin: String?
            let diffCoin: String?
            let compressed: String?

            private enum CodingKeys: String, CodingKey {
                case s, u, c
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                snapshotCoin = (try? container.decodeIfPresent(SnapshotCoin.self, forKey: .s))?.coin
                diffCoin = (try? container.decodeIfPresent(DiffCoin.self, forKey: .u))?.c
                compressed = try? container.decodeIfPresent(String.self, forKey: .c)
            }
        }

        /// A book snapshot's coin.
        struct SnapshotCoin: Decodable {
            let coin: String
        }

        /// A book diff's coin.
        struct DiffCoin: Decodable {
            let c: String
        }

        let channel: String
        let data: Fields?
        let bookUpdate: BookUpdate?

        private enum CodingKeys: String, CodingKey {
            case channel, data
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            channel = try container.decode(String.self, forKey: .channel)
            data = try? container.decodeIfPresent(Fields.self, forKey: .data)
            bookUpdate = channel == "l2" ? try? container.decodeIfPresent(BookUpdate.self, forKey: .data) : nil
        }
    }
}
