import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Market orders")
    struct MarketOrderTests {
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5},{"name":"ETH","szDecimals":4}]}"#
        private static let mids = #"{"BTC":"60243.5","ETH":"2014.35"}"#
        private static let filled = #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"filled":{"totalSz":"0.5","avgPx":"60250.0","oid":3}}]}}}"#

        private static func transport(_ answers: String...) -> FakeTransport {
            FakeTransport(responses: answers.map { TransportResponse(status: 200, body: Data($0.utf8)) })
        }

        private static func state(_ size: String) -> String {
            #"{"marginSummary":{"accountValue":"1","totalNtlPos":"0","totalRawUsd":"1","totalMarginUsed":"0"},"crossMarginSummary":{"accountValue":"1","totalNtlPos":"0","totalRawUsd":"1","totalMarginUsed":"0"},"withdrawable":"1","assetPositions":[{"type":"oneWay","position":{"coin":"BTC","szi":""#
                + size
                + #"","leverage":{"type":"cross","value":20},"entryPx":"60000","positionValue":"30000","unrealizedPnl":"0","returnOnEquity":"0","marginUsed":"1500"}}]}"#
        }

        private static func orderBody(_ transport: FakeTransport) async throws -> String {
            let body = try #require(await transport.bodies.last)
            let action = try #require(body.split(separator: #","nonce""#).first)
            return String(action)
        }

        @Test func `a market buy is an immediate-or-cancel order at the mid plus 5 %, rounded`() async throws {
            let transport = Self.transport(Self.meta, Self.mids, Self.filled)
            let results = try await OrderEndpoints.test(transport).place([.market(.buy, "BTC", size: Decimal(string: "0.5")!)])
            #expect(results.first?.status == .filled)
            #expect(await transport.bodies[1] == #"{"type":"allMids","dex":""}"#)
            #expect(
                try await Self.orderBody(transport)
                    == #"{"action":{"type":"order","orders":[{"a":0,"b":true,"p":"63256","s":"0.5","r":false,"t":{"limit":{"tif":"Ioc"}}}],"grouping":"na"}"#
            )
        }

        @Test func `an explicit price replaces the mid`() async throws {
            let transport = Self.transport(Self.meta, Self.filled)
            _ = try await OrderEndpoints.test(transport).place([
                .market(.sell, "ETH", size: 1, price: Decimal(string: "2014.35")!, slippage: .percent(5)),
            ])
            #expect(await transport.requests.count == 2)
            #expect(try await Self.orderBody(transport).contains(#""a":1,"b":false,"p":"1913.6","#))
        }

        @Test(arguments: [Hyperliquid.Slippage.percent(-1), .percent(100), .fraction(Decimal(string: "1.5")!)])
        func `slippage below 0 or at 100 % or more throws an invalid request before the order is sent`(
            slippage: Hyperliquid.Slippage
        ) async {
            let transport = Self.transport(Self.meta)
            await #expect {
                try await OrderEndpoints.test(transport).place([.market(.buy, "BTC", size: 1, slippage: slippage)])
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.count == 1)
        }

        @Test func `a coin without a mid price throws no mid price`() async {
            let transport = Self.transport(Self.meta, #"{"ETH":"2014.35"}"#)
            await #expect {
                try await OrderEndpoints.test(transport).place([.market(.buy, "BTC", size: 1)])
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .noMidPrice
            }
        }

        @Test func `closing a short buys back its whole size with a reduce-only market order`() async throws {
            let transport = Self.transport(Self.meta, Self.state("-0.5"), Self.mids, Self.filled)
            let account: Hyperliquid.Address = "0x0000000000000000000000000000000000000001"
            let results = try await OrderEndpoints.test(transport, account: account).close("BTC")
            #expect(results.first?.filledSize == Decimal(string: "0.5"))
            #expect(
                await transport.bodies[1]
                    == #"{"type":"clearinghouseState","user":"0x0000000000000000000000000000000000000001","dex":""}"#
            )
            #expect(try await Self.orderBody(transport).contains(#""b":true,"p":"63256","s":"0.5","r":true,"t":{"limit":{"tif":"Ioc"}}"#))
        }

        @Test func `closing part of a long sells the given size`() async throws {
            let transport = Self.transport(Self.meta, Self.state("0.5"), Self.mids, Self.filled)
            _ = try await OrderEndpoints.test(transport, account: "0x0000000000000000000000000000000000000001")
                .close("BTC", size: Decimal(string: "0.2")!)
            #expect(try await Self.orderBody(transport).contains(#""b":false,"p":"57231","s":"0.2","r":true,"#))
        }

        @Test func `closing without a position sends nothing and returns no results`() async throws {
            let empty = #"{"marginSummary":{"accountValue":"1","totalNtlPos":"0","totalRawUsd":"1","totalMarginUsed":"0"},"crossMarginSummary":{"accountValue":"1","totalNtlPos":"0","totalRawUsd":"1","totalMarginUsed":"0"},"withdrawable":"1","assetPositions":[]}"#
            let transport = Self.transport(Self.meta, empty)
            let results = try await OrderEndpoints.test(transport, account: "0x0000000000000000000000000000000000000001")
                .close("BTC")
            #expect(results.isEmpty)
            #expect(await transport.requests.count == 2)
        }

        @Test func `market orders in one call read each perp DEX's mids once and keep their client IDs`() async throws {
            let both = #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":1}},{"resting":{"oid":2}}]}}}"#
            let transport = Self.transport(Self.meta, Self.mids, both)
            let clientID = try Hyperliquid.ClientOrderID("0x0000000000000000000000000000000a")
            _ = try await OrderEndpoints.test(transport).place([
                .market(.buy, "BTC", size: 1, clientID: clientID), .market(.sell, "ETH", size: 1),
            ])
            #expect(await transport.bodies.filter { $0.contains("allMids") }.count == 1)
            let body = try await Self.orderBody(transport)
            #expect(body.contains(#""t":{"limit":{"tif":"Ioc"}},"c":"0x0000000000000000000000000000000a"}"#))
            #expect(body.contains(#""a":1,"b":false,"p":"1913.6","#))
        }

        @Test func `a builder-deployed perpetual's market order reads its perp DEX's mids`() async throws {
            let transport = Self.transport(
                #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#,
                #"{"universe":[{"name":"xyz:XYZ100","szDecimals":4}]}"#, #"{"xyz:XYZ100":"25947.0"}"#, Self.filled
            )
            _ = try await OrderEndpoints.test(transport).place([.market(.buy, "xyz:XYZ100", size: 1)])
            #expect(await transport.bodies[2] == #"{"type":"allMids","dex":"xyz"}"#)
            #expect(try await Self.orderBody(transport).contains(#""a":110000,"b":true,"p":"27244","#))
        }

        @Test func `a price of zero counts as none and uses the mid`() async throws {
            let transport = Self.transport(Self.meta, Self.mids, Self.filled)
            _ = try await OrderEndpoints.test(transport).place([.market(.buy, "BTC", size: 1, price: 0)])
            #expect(try await Self.orderBody(transport).contains(#""p":"63256""#))
        }

        @Test func `a modification can't be a market order`() async {
            let transport = FakeTransport()
            await #expect {
                try await OrderEndpoints.test(transport).modify([.init(.id(.init(rawValue: 1)), to: .market(.buy, "BTC", size: 1))])
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `closing with a size of zero closes the whole position`() async throws {
            let transport = Self.transport(Self.meta, Self.state("0.5"), Self.mids, Self.filled)
            _ = try await OrderEndpoints.test(transport, account: "0x0000000000000000000000000000000000000001").close("BTC", size: 0)
            #expect(try await Self.orderBody(transport).contains(#""s":"0.5","r":true,"#))
        }

        @Test func `bad slippage on a close throws even without a position`() async {
            let transport = FakeTransport()
            await #expect {
                try await OrderEndpoints.test(transport, account: "0x0000000000000000000000000000000000000001")
                    .close("BTC", slippage: .percent(100))
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `a client with a vault closes the vault's position`() async throws {
            let transport = Self.transport(Self.meta, Self.state("0.5"), Self.mids, Self.filled)
            let client = Hyperliquid.Client(
                account: "0x0000000000000000000000000000000000000001", signer: SigningVectors.pythonTestSigner,
                configuration: .init(vaultAddress: "0x1719884eb866cb12b2287399b15f7db5e7d775ea"), transport: transport
            )
            _ = try await client.order.close("BTC")
            #expect(await transport.bodies[1].contains(#""user":"0x1719884eb866cb12b2287399b15f7db5e7d775ea""#))
        }

        @Test func `closing without a signer throws before anything is sent`() async {
            let transport = FakeTransport()
            await #expect {
                try await OrderEndpoints.test(transport, signer: nil).close("BTC")
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .missingSigner
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}
