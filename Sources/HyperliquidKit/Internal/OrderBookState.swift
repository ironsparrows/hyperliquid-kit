import Foundation
import HyperliquidKitCore

/// A book kept up to date from `l2` diffs, starting from the snapshot Hyperliquid sends first.
struct OrderBookState: Sendable {
    private(set) var book: Hyperliquid.OrderBook

    init(snapshot: Hyperliquid.OrderBook) {
        book = snapshot
    }

    /// Applies a diff to each side: removes the levels at its indexes into the book as it was, then adds
    /// or replaces its levels by price, then sorts the side best price first.
    ///
    /// - Throws: ``HyperliquidError`` with kind `unexpectedResponse` when the diff removes
    ///   a level the book doesn't have, which means the book no longer matches Hyperliquid's.
    mutating func apply(_ diff: OrderBookDiff) throws {
        book = Hyperliquid.OrderBook(
            coin: book.coin, time: diff.time,
            bids: try Self.side(book.bids, removing: diff.removedBids, adding: diff.bids) { $0 > $1 },
            asks: try Self.side(book.asks, removing: diff.removedAsks, adding: diff.asks) { $0 < $1 }
        )
    }

    private static func side(
        _ levels: [Hyperliquid.OrderBook.Level], removing removed: [Int], adding added: [Hyperliquid.OrderBook.Level],
        bestFirst: (Decimal, Decimal) -> Bool
    ) throws -> [Hyperliquid.OrderBook.Level] {
        var levels = levels
        // From the last index down, so each index still points into the book as it was.
        for index in Set(removed).sorted(by: >) {
            guard levels.indices.contains(index) else {
                throw HyperliquidError(
                    .unexpectedResponse,
                    message: "A book diff removes level \(index) of a side with \(levels.count): the book is out of step"
                )
            }
            levels.remove(at: index)
        }
        for level in added {
            if let index = levels.firstIndex(where: { $0.price == level.price }) {
                levels[index] = level
            } else {
                levels.append(level)
            }
        }
        return levels.sorted { bestFirst($0.price, $1.price) }
    }
}

/// An `l2` diff: `{"c": coin, "t": time, "l": [bids, asks] added or changed, "r": [bids, asks] removed
/// indexes}`, levels `{"p": price, "s": size}` without an order count.
struct OrderBookDiff: Decodable, Sendable {
    let time: Date
    let bids: [Hyperliquid.OrderBook.Level]
    let asks: [Hyperliquid.OrderBook.Level]
    let removedBids: [Int]
    let removedAsks: [Int]

    private enum CodingKeys: String, CodingKey {
        case t, l, r
    }

    private struct Level: Decodable {
        let p: WireDecimal
        let s: WireDecimal

        var level: Hyperliquid.OrderBook.Level {
            .init(price: p.value, size: s.value, orderCount: nil)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(WireDate.self, forKey: .t).value
        var levels = try container.nestedUnkeyedContainer(forKey: .l)
        bids = try levels.decode([Level].self).map(\.level)
        asks = try levels.decode([Level].self).map(\.level)
        var removed = try container.nestedUnkeyedContainer(forKey: .r)
        removedBids = try removed.decode([Int].self)
        removedAsks = try removed.decode([Int].self)
    }
}
