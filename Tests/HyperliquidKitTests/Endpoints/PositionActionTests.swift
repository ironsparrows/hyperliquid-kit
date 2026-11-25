import Foundation
import Testing

@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Leverage, margin and TWAP actions")
    struct PositionActionTests {
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5},{"name":"ETH","szDecimals":4}]}"#
        private static let accepted = #"{"status":"ok","response":{"type":"default"}}"#
        private static let signature = #""signature":{"r":"#

        private static func transport(_ answers: String...) -> FakeTransport {
            FakeTransport(responses: answers.map { TransportResponse(status: 200, body: Data($0.utf8)) })
        }

        /// The `action` of the last request, as sent.
        private static func action(_ transport: FakeTransport) async throws -> String {
            let request = try #require(await transport.requests.last)
            #expect(request.url.absoluteString == "https://api.hyperliquid.xyz/exchange")
            let body = String(decoding: request.body, as: UTF8.self)
            let start = try #require(body.range(of: #"{"action":"#)).upperBound
            let end = try #require(body.range(of: #","nonce":"#)).lowerBound
            return String(body[start..<end])
        }

        // MARK: Leverage and margin

        @Test(arguments: [
            (Hyperliquid.Leverage.cross(10), #"{"type":"updateLeverage","asset":1,"isCross":true,"leverage":10}"#),
            (.isolated(3), #"{"type":"updateLeverage","asset":1,"isCross":false,"leverage":3}"#),
        ])
        func `setting leverage sends the asset, the margin mode and the leverage`(
            leverage: Hyperliquid.Leverage, action: String
        ) async throws {
            let transport = Self.transport(Self.meta, Self.accepted)
            try await PositionEndpoints.test(transport).setLeverage(leverage, for: "ETH")
            #expect(try await Self.action(transport) == action)
        }

        @Test func `leverage with a mode other than cross or isolated throws before anything is sent`() async {
            let transport = FakeTransport()
            await #expect {
                try await PositionEndpoints.test(transport).setLeverage(.init(mode: .strictIsolated, value: 3), for: "ETH")
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test(arguments: [
            (Decimal(1), #"{"type":"updateIsolatedMargin","asset":0,"isBuy":true,"ntli":1000000}"#),
            (Decimal(string: "-2.5")!, #"{"type":"updateIsolatedMargin","asset":0,"isBuy":true,"ntli":-2500000}"#),
            (Decimal(string: "0.000001")!, #"{"type":"updateIsolatedMargin","asset":0,"isBuy":true,"ntli":1}"#),
        ])
        func `adjusting margin sends the amount in millionths of a dollar`(amount: Decimal, action: String) async throws {
            let transport = Self.transport(Self.meta, Self.accepted)
            try await PositionEndpoints.test(transport).adjustMargin("BTC", by: amount)
            #expect(try await Self.action(transport) == action)
        }

        @Test func `a margin amount with more than 6 decimals throws before anything is sent`() async {
            let transport = FakeTransport()
            await #expect {
                try await PositionEndpoints.test(transport).adjustMargin("BTC", by: Decimal(string: "0.0000001")!)
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `topping up margin sends the leverage as text`() async throws {
            let transport = Self.transport(Self.meta, Self.accepted)
            try await PositionEndpoints.test(transport).topUpMargin("ETH", toLeverage: Decimal(string: "2.50")!)
            #expect(try await Self.action(transport) == #"{"type":"topUpIsolatedOnlyMargin","asset":1,"leverage":"2.5"}"#)
        }

        // MARK: TWAP

        @Test func `placing a TWAP sends its fields in order and returns its ID`() async throws {
            let running = #"{"status":"ok","response":{"type":"twapOrder","data":{"status":{"running":{"twapId":77738308}}}}}"#
            let transport = Self.transport(Self.meta, running)
            let result = try await TwapEndpoints.test(transport).place(
                .init(.sell, "ETH", size: Decimal(string: "0.010")!, duration: .seconds(300), reduceOnly: true, randomize: true)
            )
            #expect(result == .init(twapID: .init(rawValue: 77_738_308), error: nil))
            #expect(result.isRunning)
            #expect(
                try await Self.action(transport)
                    == #"{"type":"twapOrder","twap":{"a":1,"b":false,"s":"0.01","r":true,"m":5,"t":true}}"#
            )
        }

        @Test func `a rejected TWAP returns Hyperliquid's reason`() async throws {
            let rejected = #"{"status":"ok","response":{"type":"twapOrder","data":{"status":{"error":"Invalid TWAP duration: 1 min(s)"}}}}"#
            let transport = Self.transport(Self.meta, rejected)
            let result = try await TwapEndpoints.test(transport).place(.init(.buy, "BTC", size: 1, duration: .seconds(60)))
            #expect(result == .init(twapID: nil, error: "Invalid TWAP duration: 1 min(s)"))
        }

        @Test(arguments: [Duration.seconds(90), .milliseconds(60_500)])
        func `a TWAP duration that isn't whole minutes throws before anything is sent`(duration: Duration) async {
            let transport = FakeTransport()
            await #expect {
                _ = try await TwapEndpoints.test(transport).place(.init(.buy, "BTC", size: 1, duration: duration))
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `canceling a TWAP sends the asset and the TWAP ID`() async throws {
            let success = #"{"status":"ok","response":{"type":"twapCancel","data":{"status":"success"}}}"#
            let failure =
                #"{"status":"ok","response":{"type":"twapCancel","data":{"status":{"error":"TWAP was never placed, already canceled, or filled."}}}}"#
            let transport = Self.transport(Self.meta, success, failure)
            let twap = TwapEndpoints.test(transport)
            #expect(try await twap.cancel(.init(rawValue: 3156), coin: "ETH").isCanceled)
            #expect(
                try await twap.cancel(.init(rawValue: 3156), coin: "ETH").error == "TWAP was never placed, already canceled, or filled.")
            #expect(try await Self.action(transport) == #"{"type":"twapCancel","a":1,"t":3156}"#)
        }

        @Test(arguments: [#"{"status":"ok"}"#, #"{"status":"ok","response":{"type":"default"}}"#])
        func `a TWAP answer without a status throws an unexpected response with the nonce`(answer: String) async {
            let transport = Self.transport(Self.meta, answer)
            await #expect {
                _ = try await TwapEndpoints.test(transport, nonce: 42).place(.init(.buy, "BTC", size: 1, duration: .seconds(300)))
            } throws: { error in
                let error = error as? HyperliquidError
                return error?.kind == .unexpectedResponse && error?.nonce == 42
            }
        }

        @Test func `an accepted answer with no response at all says it has no status`() async {
            let transport = Self.transport(Self.meta, #"{"status":"ok"}"#)
            await #expect {
                _ = try await TwapEndpoints.test(transport).cancel(.init(rawValue: 1), coin: "BTC")
            } throws: { error in
                (error as? HyperliquidError)?.message == "The answer has no status"
            }
        }

        // MARK: Shared rules

        /// Every action this suite covers, on `coin`.
        private static func actions(
            _ position: PositionEndpoints, _ twap: TwapEndpoints, _ coin: Hyperliquid.Coin, expiresAfter: Date? = nil
        ) -> [@Sendable () async throws -> Void] {
            [
                { try await position.setLeverage(.cross(5), for: coin, expiresAfter: expiresAfter) },
                { try await position.adjustMargin(coin, by: 1, expiresAfter: expiresAfter) },
                { try await position.topUpMargin(coin, toLeverage: 2, expiresAfter: expiresAfter) },
                { _ = try await twap.place(.init(.buy, coin, size: 1, duration: .seconds(300)), expiresAfter: expiresAfter) },
                { _ = try await twap.cancel(.init(rawValue: 1), coin: coin, expiresAfter: expiresAfter) },
            ]
        }

        @Test(arguments: ["@107", "#10"] as [Hyperliquid.Coin])
        func `spot and outcome coins throw unsupported market without a request`(coin: Hyperliquid.Coin) async {
            let transport = FakeTransport()
            for action in Self.actions(.test(transport), .test(transport), coin) {
                await #expect {
                    try await action()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
                }
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `a client without a signer throws missing signer without a request`() async {
            let transport = FakeTransport()
            let actions = Self.actions(.test(transport, signer: nil), .test(transport, signer: nil), "BTC")
            for action in actions {
                await #expect {
                    try await action()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .missingSigner
                }
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test(arguments: 0..<5)
        func `each rejected action throws with its nonce and sends its expiry`(index: Int) async throws {
            let rejected = #"{"status":"err","response":"Rejected for the test."}"#
            let transport = Self.transport(Self.meta, rejected)
            let expiry = Date(timeIntervalSince1970: 1_795_500_000)
            let action = Self.actions(.test(transport, nonce: 7), .test(transport, nonce: 7), "BTC", expiresAfter: expiry)[index]
            await #expect {
                try await action()
            } throws: { error in
                let error = error as? HyperliquidError
                return error?.kind == .actionRejected && error?.nonce == 7 && error?.message == "Rejected for the test."
            }
            let body = String(decoding: try #require(await transport.requests.last).body, as: UTF8.self)
            #expect(body.contains(#""nonce":7,"#))
            #expect(body.contains(Self.signature))
            #expect(body.hasSuffix(#""vaultAddress":null,"expiresAfter":1795500000000}"#))
        }

        /// Inputs that can't be sent, each on one action.
        private static let invalidInputs: [@Sendable (PositionEndpoints, TwapEndpoints) async throws -> Void] = [
            { position, _ in try await position.adjustMargin("BTC", by: .nan) },
            { position, _ in try await position.adjustMargin("BTC", by: 10_000_000_000_000) },
            { position, _ in try await position.adjustMargin("BTC", by: Decimal(string: "1.000000001")!) },
            { position, _ in try await position.topUpMargin("BTC", toLeverage: Decimal(string: "1.000000001")!) },
            { position, _ in try await position.topUpMargin("BTC", toLeverage: .nan) },
            { _, twap in _ = try await twap.place(.init(.buy, "BTC", size: Decimal(string: "0.000000001")!, duration: .seconds(300))) },
            { _, twap in _ = try await twap.place(.init(.buy, "BTC", size: .nan, duration: .seconds(300))) },
        ]

        @Test(arguments: 0..<7)
        func `inputs that can't be sent throw invalid request before anything is sent`(index: Int) async {
            let transport = FakeTransport()
            await #expect {
                try await Self.invalidInputs[index](.test(transport), .test(transport))
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}
