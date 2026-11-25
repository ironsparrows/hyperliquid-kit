import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Order and TWAP requests")
    struct OrderRequestsTests {
        private static let account: Hyperliquid.Address = "0x00000000000000000000000000000000000000a1"
        private static let user = #""user":"0x00000000000000000000000000000000000000a1""#

        @Test func `pending orders send the user and the perp DEX, in both forms`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let order = Self.order(transport)
            _ = try await order.pending()
            _ = try await order.pendingDetailed(dex: .named("xyz"))
            #expect(await transport.bodies == [
                "{\"type\":\"openOrders\",\(Self.user),\"dex\":\"\"}",
                "{\"type\":\"frontendOpenOrders\",\(Self.user),\"dex\":\"xyz\"}",
            ])
        }

        @Test func `an order status sends an order ID as a number and a client ID as text`() async throws {
            let transport = FakeTransport(responses: [.json(#"{"status":"unknownOid"}"#), .json(#"{"status":"unknownOid"}"#)])
            let order = Self.order(transport)
            #expect(try await order.status(.id(.init(rawValue: 91_490_942))) == nil)
            #expect(try await order.status(.clientID(try .init("0x00000000000000000000000000000001"))) == nil)
            #expect(await transport.bodies == [
                "{\"type\":\"orderStatus\",\(Self.user),\"oid\":91490942}",
                "{\"type\":\"orderStatus\",\(Self.user),\"oid\":\"0x00000000000000000000000000000001\"}",
            ])
        }

        @Test func `history sends the user`() async throws {
            let transport = FakeTransport(json: "[]")
            _ = try await Self.order(transport).history()
            #expect(await transport.bodies == ["{\"type\":\"historicalOrders\",\(Self.user)}"])
        }

        @Test func `fills send aggregateByTime only when it is true`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let order = Self.order(transport)
            _ = try await order.fills()
            _ = try await order.fills(aggregateByTime: true)
            #expect(await transport.bodies == [
                "{\"type\":\"userFills\",\(Self.user)}",
                "{\"type\":\"userFills\",\(Self.user),\"aggregateByTime\":true}",
            ])
        }

        @Test func `fills by time always send the end time, null when there is none, and aggregateByTime`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let order = Self.order(transport)
            let start = Date(timeIntervalSince1970: 1_795_500_000)
            _ = try await order.fills(from: start)
            _ = try await order.fills(from: start, to: start.addingTimeInterval(60), aggregateByTime: true)
            #expect(await transport.bodies == [
                "{\"type\":\"userFillsByTime\",\(Self.user),\"startTime\":1795500000000,\"endTime\":null,\"aggregateByTime\":false}",
                "{\"type\":\"userFillsByTime\",\(Self.user),\"startTime\":1795500000000,\"endTime\":1795500060000,\"aggregateByTime\":true}",
            ])
        }

        @Test func `TWAP reads send the user`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let twap = TwapEndpoints.test(transport, account: Self.account)
            _ = try await twap.sliceFills()
            _ = try await twap.history()
            #expect(await transport.bodies == [
                "{\"type\":\"userTwapSliceFills\",\(Self.user)}", "{\"type\":\"twapHistory\",\(Self.user)}",
            ])
        }

        @Test func `an address given to a read wins over the client's account`() async throws {
            let transport = FakeTransport(json: "[]")
            _ = try await Self.order(transport).history(for: "0x00000000000000000000000000000000000000b2")
            #expect(await transport.bodies == [
                #"{"type":"historicalOrders","user":"0x00000000000000000000000000000000000000b2"}"#
            ])
        }

        @Test func `reads without an account throw missing account before sending`() async {
            let transport = FakeTransport()
            let order = OrderEndpoints.test(transport, account: nil)
            let twap = TwapEndpoints.test(transport)
            let reads: [@Sendable () async throws -> Void] = [
                { _ = try await order.pending() }, { _ = try await order.pendingDetailed() },
                { _ = try await order.status(.id(.init(rawValue: 1))) }, { _ = try await order.history() },
                { _ = try await order.fills() }, { _ = try await order.fills(from: .now) },
                { _ = try await twap.sliceFills() }, { _ = try await twap.history() },
            ]
            for read in reads {
                await #expect {
                    try await read()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .missingAccount
                }
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `the client's account reaches order and TWAP reads`() async throws {
            let transport = FakeTransport(responses: [.json("[]"), .json("[]")])
            let client = Hyperliquid.Client(account: Self.account, configuration: .init(), transport: transport)
            _ = try await client.order.pending()
            _ = try await client.twap.sliceFills()
            #expect(await transport.bodies == [
                "{\"type\":\"openOrders\",\(Self.user),\"dex\":\"\"}", "{\"type\":\"userTwapSliceFills\",\(Self.user)}",
            ])
        }

        private static func order(_ transport: FakeTransport) -> OrderEndpoints {
            OrderEndpoints.test(transport, account: Self.account)
        }
    }
}
