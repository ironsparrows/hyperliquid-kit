import Foundation
import Testing

@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Asset directory", .timeLimit(.minutes(1)))
    struct AssetDirectoryTests {
        private static let meta =
            #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":40,"marginTableId":40},{"name":"ETH","szDecimals":4,"maxLeverage":25,"marginTableId":25}],"marginTables":[]}"#
        private static let perpDexs =
            #"[null,{"name":"flx","fullName":"Felix","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"},{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#
        private static let xyzMeta =
            #"{"universe":[{"name":"xyz:A","szDecimals":2,"maxLeverage":10,"marginTableId":10},{"name":"xyz:B","szDecimals":3,"maxLeverage":10,"marginTableId":10}],"marginTables":[]}"#

        @Test func `a perpetual's asset ID is its index on the first perp DEX`() async throws {
            let directory = AssetDirectory(info: .test(FakeTransport(json: Self.meta)))
            #expect(try await directory.asset(for: "BTC") == .init(id: 0, sizeDecimals: 5))
            #expect(try await directory.asset(for: "ETH") == .init(id: 1, sizeDecimals: 4))
        }

        @Test func `a builder-deployed perpetual's ID is offset by its perp DEX's position`() async throws {
            let transport = FakeTransport(responses: [Self.perpDexs, Self.xyzMeta].map { .init(status: 200, body: Data($0.utf8)) })
            let directory = AssetDirectory(info: .test(transport))
            #expect(try await directory.asset(for: "xyz:B") == .init(id: 120_001, sizeDecimals: 3))
            #expect(await transport.bodies == [#"{"type":"perpDexs"}"#, #"{"type":"meta","dex":"xyz"}"#])
        }

        @Test func `a perp DEX's meta loads once`() async throws {
            let transport = FakeTransport(json: Self.meta)
            let directory = AssetDirectory(info: .test(transport))
            _ = try await directory.asset(for: "BTC")
            _ = try await directory.asset(for: "ETH")
            #expect(await transport.requests.count == 1)
        }

        @Test func `lookups made at the same time share one load`() async throws {
            let transport = FakeTransport(json: Self.meta)
            let directory = AssetDirectory(info: .test(transport))
            async let btc = directory.asset(for: "BTC")
            async let eth = directory.asset(for: "ETH")
            #expect(try await [btc.id, eth.id] == [0, 1])
            #expect(await transport.requests.count == 1)
        }

        @Test func `a cancelled lookup returns at once, and the load it shares goes on for the others`() async throws {
            let transport = HeldTransport(answer: Self.meta)
            let directory = AssetDirectory(info: .test(transport))
            let cancelled = Task { try await directory.asset(for: "BTC") }
            let waiting = Task { try await directory.asset(for: "ETH") }
            try await eventually { await transport.held ? true : nil }
            cancelled.cancel()
            await #expect(throws: CancellationError.self) { try await cancelled.value }
            await transport.release()
            #expect(try await waiting.value.id == 1)
            #expect(await transport.requests == 1)
        }

        @Test func `a failed perp DEX list is tried again on the next lookup`() async throws {
            let transport = FakeTransport(responses: [
                .init(status: 500, body: Data("null".utf8)), .init(status: 200, body: Data(Self.perpDexs.utf8)),
                .init(status: 200, body: Data(Self.xyzMeta.utf8)),
            ])
            let directory = AssetDirectory(info: .test(transport))
            await #expect(throws: HyperliquidError.self) { try await directory.asset(for: "xyz:A") }
            #expect(try await directory.asset(for: "xyz:A").id == 120_000)
        }

        @Test func `fields other than the name and size decimals don't stop a lookup`() async throws {
            let json = #"{"universe":[{"name":"BTC","szDecimals":5,"maxLeverage":"odd","marginTableId":99}],"marginTables":[]}"#
            let directory = AssetDirectory(info: .test(FakeTransport(json: json)))
            #expect(try await directory.asset(for: "BTC").sizeDecimals == 5)
        }

        @Test func `a coin the loaded meta doesn't list throws unknown coin without reloading`() async throws {
            let transport = FakeTransport(json: Self.meta)
            let directory = AssetDirectory(info: .test(transport))
            _ = try await directory.asset(for: "BTC")
            await #expect {
                try await directory.asset(for: "NOPE")
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unknownCoin
            }
            #expect(await transport.requests.count == 1)
        }

        @Test(arguments: ["@107", "PURR/USDC", "#10"] as [Hyperliquid.Coin])
        func `a spot or outcome coin throws unsupported market without loading`(coin: Hyperliquid.Coin) async {
            let transport = FakeTransport()
            await #expect {
                try await AssetDirectory(info: .test(transport)).asset(for: coin)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `a failed load is tried again on the next lookup`() async throws {
            let transport = FakeTransport(responses: [
                .init(status: 500, body: Data("null".utf8)), .init(status: 200, body: Data(Self.meta.utf8)),
            ])
            let directory = AssetDirectory(info: .test(transport))
            await #expect(throws: HyperliquidError.self) { try await directory.asset(for: "BTC") }
            #expect(try await directory.asset(for: "BTC").id == 0)
        }
    }
}

/// Holds every request until `release()`, then answers each with `answer`.
private actor HeldTransport: HTTPTransport {
    private let answer: String
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var requests = 0

    init(answer: String) {
        self.answer = answer
    }

    var held: Bool { !waiting.isEmpty }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        requests += 1
        if !released { await withCheckedContinuation { waiting.append($0) } }
        return .json(answer)
    }

    func release() {
        released = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
