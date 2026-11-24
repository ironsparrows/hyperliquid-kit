import Foundation
import HyperliquidKitCore

/// Live pushes over the client's ``StreamConnection``.
struct Streams: Hyperliquid.StreamAPI {
    let connection: StreamConnection

    func mids(dex: Hyperliquid.PerpDex) -> AsyncThrowingStream<[Hyperliquid.Coin: Decimal], any Error> {
        connection.stream(.allMids(dex), bufferingPolicy: .bufferingNewest(1)) { data in
            try JSONDecoder().decode(Push<MidsPush>.self, from: data).data.mids.mapValues(\.value)
        }
    }

    func disconnect() async {
        await connection.disconnect()
    }
}

// MARK: - Subscriptions

extension StreamConnection.Subscription {
    /// `allMids`, with `dex` for a builder-deployed perp DEX, which is checked first; a push from the
    /// first perp DEX carries no `dex`.
    static func allMids(_ dex: Hyperliquid.PerpDex) -> Self {
        Self(
            topic: .init(channel: "allMids", key: dex.name),
            request: dex == .first ? ["type": "allMids"] : ["type": "allMids", "dex": .string(dex.name)],
            dex: dex
        )
    }
}

// MARK: - Wire

/// `{"channel": …, "data": …}`.
private struct Push<Payload: Decodable>: Decodable {
    let data: Payload
}

/// `allMids` data: `{"mids": {coin: "price"}, "dex"?}`.
private struct MidsPush: Decodable {
    let mids: [Hyperliquid.Coin: WireDecimal]
}
