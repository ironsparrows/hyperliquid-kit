import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Order actions")
    struct OrderActionTests {
        // `meta` with BTC at index 0 and ETH at 1, so an ETH order uses asset 1 as the Python SDK's vectors do.
        private static let meta = #"{"universe":[{"name":"BTC","szDecimals":5},{"name":"ETH","szDecimals":4}]}"#
        private static let resting = #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":77738308}}]}}}"#
        private static let accepted = #"{"status":"ok","response":{"type":"default"}}"#

        private static func transport(_ answers: String...) -> FakeTransport {
            FakeTransport(responses: answers.map { TransportResponse(status: 200, body: Data($0.utf8)) })
        }

        private static func exchangeBody(_ transport: FakeTransport) async throws -> String {
            let request = try #require(await transport.requests.last)
            #expect(request.url.absoluteString == "https://api.hyperliquid.xyz/exchange")
            return String(decoding: request.body, as: UTF8.self)
        }

        // The Python SDK's `signing_test.py` signs these actions with nonce 0 on mainnet, so the bodies
        // carry its published signatures.
        @Test func `a limit order is sent exactly as the Python SDK signs it`() async throws {
            let transport = Self.transport(Self.meta, Self.resting)
            let results = try await OrderRequests.test(transport).place([
                .limit(.buy, "ETH", price: 100, size: 100),
            ])
            #expect(results == [.init(status: .resting, orderID: .init(rawValue: 77_738_308))])
            #expect(
                try await Self.exchangeBody(transport)
                    == #"{"action":{"type":"order","orders":[{"a":1,"b":true,"p":"100","s":"100","r":false,"t":{"limit":{"tif":"Gtc"}}}],"grouping":"na"},"nonce":0,"signature":{"r":"0xd65369825a9df5d80099e513cce430311d7d26ddf477f5b3a33d2806b100d78e","s":"0x2b54116ff64054968aa237c20ca9ff68000f977c93289157748a3162b6ea940e","v":28},"vaultAddress":null,"expiresAfter":null}"#
            )
        }

        @Test func `an order with a client order ID signs as the Python SDK's vector`() async throws {
            let transport = Self.transport(Self.meta, Self.resting)
            let clientID = try Hyperliquid.ClientOrderID("0x00000000000000000000000000000001")
            _ = try await OrderRequests.test(transport).place([.limit(.buy, "ETH", price: 100, size: 100, clientID: clientID)])
            let body = try await Self.exchangeBody(transport)
            #expect(body.contains(#""c":"0x00000000000000000000000000000001"}],"#))
            #expect(body.contains(#""r":"0x41ae18e8239a56cacbc5dad94d45d0b747e5da11ad564077fcac71277a946e3""#))
        }

        @Test func `a stop-loss trigger order signs as the Python SDK's vector`() async throws {
            let transport = Self.transport(Self.meta, Self.resting)
            _ = try await OrderRequests.test(transport).place([
                .trigger(.buy, "ETH", .stopLoss, triggerPrice: 103, size: 100, execution: .market(limitPrice: 100), reduceOnly: false),
            ])
            let body = try await Self.exchangeBody(transport)
            #expect(body.contains(#""t":{"trigger":{"isMarket":true,"triggerPx":"103","tpsl":"sl"}}"#))
            #expect(body.contains(#""r":"0x98343f2b5ae8e26bb2587daad3863bc70d8792b09af1841b6fdd530a2065a3f9""#))
        }

        @Test func `scheduling and clearing a cancel sign as the Python SDK's vectors`() async throws {
            let transport = Self.transport(Self.accepted, Self.accepted)
            let order = OrderRequests.test(transport, nonce: 0)
            try await order.scheduleCancelAll(at: Date(timeIntervalSince1970: 123_456.789))
            try await order.clearScheduledCancel()
            let bodies = await transport.bodies
            #expect(bodies[0].hasPrefix(#"{"action":{"type":"scheduleCancel","time":123456789},"nonce":0,"#))
            #expect(bodies[0].contains(#""r":"0x609cb20c737945d070716dcc696ba030e9976fcf5edad87afa7d877493109d55""#))
            // The second action takes the next nonce, so only its action is compared.
            #expect(bodies[1].hasPrefix(#"{"action":{"type":"scheduleCancel"},"nonce":1,"#))
        }

        @Test(arguments: [false, true])
        func `a cancel sends the fast flag only when set`(fast: Bool) async throws {
            let transport = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"cancel","data":{"statuses":["success",{"error":"Order was never placed, already canceled, or filled."}]}}}"#)
            let results = try await OrderRequests.test(transport).cancel(
                [.init(.init(rawValue: 1), coin: "BTC"), .init(.init(rawValue: 2), coin: "ETH")], fast: fast
            )
            #expect(results.map(\.isCanceled) == [true, false])
            let action = #"{"type":"cancel","cancels":[{"a":0,"o":1},{"a":1,"o":2}]"# + (fast ? #","f":true}"# : "}")
            #expect(try await Self.exchangeBody(transport).hasPrefix(#"{"action":"# + action + ","))
        }

        @Test func `a cancel by client order ID names the asset and the ID`() async throws {
            let transport = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"cancel","data":{"statuses":["success"]}}}"#)
            let clientID = try Hyperliquid.ClientOrderID("0x0000000000000000000000000000000a")
            _ = try await OrderRequests.test(transport).cancel(clientIDs: [.init(clientID, coin: "ETH")])
            #expect(
                try await Self.exchangeBody(transport).hasPrefix(
                    #"{"action":{"type":"cancelByCloid","cancels":[{"asset":1,"cloid":"0x0000000000000000000000000000000a"}]},"#
                )
            )
        }

        @Test(arguments: [false, true])
        func `a modification names the order by ID or client ID and sends always place only when set`(alwaysPlace: Bool) async throws {
            let transport = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":5}},{"resting":{"oid":6}}]}}}"#)
            let clientID = try Hyperliquid.ClientOrderID("0x0000000000000000000000000000000a")
            let new = Hyperliquid.OrderRequest.limit(.sell, "BTC", price: Decimal(string: "60000.5")!, size: Decimal(string: "0.0010")!, timeInForce: .addLiquidityOnly)
            _ = try await OrderRequests.test(transport).modify(
                [.init(.id(.init(rawValue: 9)), to: new), .init(.clientID(clientID), to: new)], alwaysPlace: alwaysPlace
            )
            let order = #"{"a":0,"b":false,"p":"60000.5","s":"0.001","r":false,"t":{"limit":{"tif":"Alo"}}}"#
            let action = #"{"type":"batchModify","modifies":[{"oid":9,"order":"# + order + #"},{"oid":"0x0000000000000000000000000000000a","order":"# + order + "}]"
                + (alwaysPlace ? #","a":true}"# : "}")
            #expect(try await Self.exchangeBody(transport).hasPrefix(#"{"action":"# + action + ","))
        }

        @Test(arguments: [
            (Hyperliquid.OrderRequest.limit(.buy, "BTC", price: Decimal(string: "0.123456789")!, size: 1), "price"),
            (.limit(.buy, "BTC", price: 1, size: Decimal(string: "1.000000001")!), "size"),
            (.trigger(.sell, "BTC", .stopLoss, triggerPrice: Decimal(string: "0.000000001")!, size: 1, execution: .limit(price: 1)), "trigger price"),
            (.limit(.buy, "BTC", price: .nan, size: 1), "price"),
        ])
        func `a number with more than 8 decimals throws an invalid request naming it before anything is sent`(
            order: Hyperliquid.OrderRequest, field: String
        ) async {
            let transport = Self.transport(Self.meta)
            await #expect {
                try await OrderRequests.test(transport).place([order])
            } throws: { error in
                guard let error = error as? Hyperliquid.ClientError else { return false }
                return error.reason == .invalidRequest && error.message?.hasPrefix("The \(field) ") == true
            }
            #expect(await transport.bodies.allSatisfy { !$0.contains("exchange") && !$0.contains("action") })
        }

        @Test func `a modification with more than 8 decimals throws before anything is sent`() async {
            let transport = Self.transport(Self.meta)
            let new = Hyperliquid.OrderRequest.limit(.buy, "BTC", price: 1, size: Decimal(string: "0.000000001")!)
            await #expect {
                try await OrderRequests.test(transport).modify([.init(.id(.init(rawValue: 1)), to: new)])
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .invalidRequest
            }
            #expect(await transport.requests.count == 1)
        }

        @Test(arguments: 0..<7)
        func `every action sends its expiry`(action: Int) async throws {
            let answers =
                switch action {
                case 0, 3: [Self.meta, Self.resting]
                case 1, 2: [Self.meta, #"{"status":"ok","response":{"type":"cancel","data":{"statuses":["success"]}}}"#]
                default: [Self.accepted]
                }
            let transport = FakeTransport(responses: answers.map { TransportResponse(status: 200, body: Data($0.utf8)) })
            let order = OrderRequests.test(transport)
            let expiry = Date(timeIntervalSince1970: 1_700_000_000)
            let limit = Hyperliquid.OrderRequest.limit(.buy, "BTC", price: 1, size: 1)
            switch action {
            case 0: _ = try await order.place([limit], grouping: .standalone, expiresAfter: expiry)
            case 1: _ = try await order.cancel([.init(.init(rawValue: 1), coin: "BTC")], fast: false, expiresAfter: expiry)
            case 2: _ = try await order.cancel(clientIDs: [.init(.random(), coin: "BTC")], fast: false, expiresAfter: expiry)
            case 3: _ = try await order.modify([.init(.id(.init(rawValue: 1)), to: limit)], alwaysPlace: false, expiresAfter: expiry)
            case 4: try await order.scheduleCancelAll(at: expiry, expiresAfter: expiry)
            case 5: try await order.clearScheduledCancel(expiresAfter: expiry)
            default: try await order.invalidate(nonce: 1, expiresAfter: expiry)
            }
            #expect(try await Self.exchangeBody(transport).hasSuffix(#""expiresAfter":1700000000000}"#))
        }

        @Test func `8 decimals are sent as written`() async throws {
            let transport = Self.transport(Self.meta, Self.resting)
            _ = try await OrderRequests.test(transport).place([.limit(.buy, "BTC", price: 1, size: Decimal(string: "0.12345678")!)])
            #expect(try await Self.exchangeBody(transport).contains(#""s":"0.12345678""#))
        }

        @Test(arguments: [(Decimal(0.001), "0.001"), (Decimal(60000.1), "60000.1"), (Decimal(3500.3), "3500.3")])
        func `a floating-point literal is sent as written`(size: Decimal, expected: String) async throws {
            let transport = Self.transport(Self.meta, Self.resting)
            // A `Decimal` made from a `Double` carries its binary error, such as 60000.0999999999985…
            _ = try await OrderRequests.test(transport).place([.limit(.buy, "BTC", price: 1, size: size)])
            #expect(try await Self.exchangeBody(transport).contains(#""s":"\#(expected)""#))
        }

        @Test func `a batch rejected with one error throws it, and another count of statuses is unexpected`() async {
            let order = Hyperliquid.OrderRequest.limit(.buy, "BTC", price: 1, size: 1)
            let rejected = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"error":"Order has invalid size."}]}}}"#)
            await #expect {
                try await OrderRequests.test(rejected).place([order, order])
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.kind == .actionRejected && error.message == "Order has invalid size."
            }
            let missing = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"resting":{"oid":1}}]}}}"#)
            await #expect {
                try await OrderRequests.test(missing).place([order, order])
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.kind == .unexpectedResponse && error.message == "1 statuses for 2 orders" && error.nonce != nil
            }
        }

        @Test func `a nonce spent by invalidating is never handed out again`() async throws {
            let transport = Self.transport(Self.accepted, Self.meta, Self.resting)
            let order = OrderRequests.test(transport, nonce: 1_000)
            try await order.invalidate(nonce: 5_000)
            _ = try await order.place([.limit(.buy, "BTC", price: 1, size: 1)])
            #expect(try await Self.exchangeBody(transport).contains(#""nonce":5001,"#))
        }

        @Test func `invalidating a nonce signs a no-op with that nonce`() async throws {
            let transport = Self.transport(Self.accepted)
            try await OrderRequests.test(transport, nonce: 5).invalidate(nonce: 1_700_000_000_123)
            #expect(try await Self.exchangeBody(transport).hasPrefix(#"{"action":{"type":"noop"},"nonce":1700000000123,"#))
        }

        @Test func `the vault and expiry are sent with the action`() async throws {
            let transport = Self.transport(Self.accepted)
            let vault: Hyperliquid.Address = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"
            try await OrderRequests.test(transport, vault: vault)
                .clearScheduledCancel(expiresAfter: Date(timeIntervalSince1970: 1_700_000_000))
            #expect(
                try await Self.exchangeBody(transport)
                    .hasSuffix(#""vaultAddress":"0x1719884eb866cb12b2287399b15f7db5e7d775ea","expiresAfter":1700000000000}"#)
            )
        }

        @Test func `a builder-deployed perpetual's order uses its offset asset ID`() async throws {
            let transport = Self.transport(
                #"[null,{"name":"xyz","fullName":"XYZ","deployer":"0x88806a71d74ad0a510b350545c9ae490912f0888"}]"#,
                #"{"universe":[{"name":"xyz:XYZ100","szDecimals":4}]}"#, Self.resting
            )
            _ = try await OrderRequests.test(transport).place([.limit(.buy, "xyz:XYZ100", price: 25_000, size: 1)])
            #expect(try await Self.exchangeBody(transport).contains(#""orders":[{"a":110000,"#))
        }

        @Test func `each order gets its own result, rejections included`() async throws {
            let statuses = #"[{"resting":{"oid":1,"cloid":"0x0000000000000000000000000000000a"}},{"filled":{"totalSz":"0.02","avgPx":"1891.4","oid":2}},{"error":"Order must have minimum value of $10."},"waitingForTrigger"]"#
            let transport = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"order","data":{"statuses":"# + statuses + "}}}")
            let order = Hyperliquid.OrderRequest.limit(.buy, "BTC", price: 1, size: 1)
            let results = try await OrderRequests.test(transport).place(Array(repeating: order, count: 4))
            #expect(results.map(\.status) == [.resting, .filled, .rejected, .init(rawValue: "waitingForTrigger")])
            #expect(results[0].clientID == (try Hyperliquid.ClientOrderID("0x0000000000000000000000000000000a")))
            #expect(results[1].filledSize == Decimal(string: "0.02") && results[1].averagePrice == Decimal(string: "1891.4"))
            #expect(results[2].error == "Order must have minimum value of $10.")
        }

        @Test func `one status for several orders throws, since it can't be matched to them`() async {
            let transport = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"error":"Invalid TP/SL price."}]}}}"#)
            let order = Hyperliquid.OrderRequest.limit(.buy, "BTC", price: 1, size: 1)
            await #expect {
                try await OrderRequests.test(transport, nonce: 42).place([order, order])
            } throws: { error in
                (error as? HyperliquidError)?.kind == .actionRejected && (error as? HyperliquidError)?.nonce == 42
            }
        }

        @Test func `a rejected action throws Hyperliquid's message with the nonce`() async {
            let transport = Self.transport(#"{"status":"err","response":"User or API Wallet 0x0459dea86a6d8a2bb4ef1bb2a1a2bd5ae44ece91 does not exist."}"#)
            await #expect {
                try await OrderRequests.test(transport, nonce: 42).clearScheduledCancel()
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.kind == .actionRejected && error.nonce == 42 && error.message?.hasPrefix("User or API Wallet") == true
            }
        }

        @Test func `an HTTP error throws its status and message with the nonce`() async {
            let transport = FakeTransport(status: 422, json: "Failed to deserialize the JSON body into the target type")
            await #expect {
                try await OrderRequests.test(transport, nonce: 42).clearScheduledCancel()
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.httpStatus == 422 && error.nonce == 42
                    && error.message == "Failed to deserialize the JSON body into the target type"
            }
        }

        @Test func `a network failure during an action carries the nonce`() async {
            await #expect {
                try await OrderRequests.test(FailingTransport(), nonce: 42).invalidate(nonce: 7)
            } throws: { error in
                guard let error = error as? Hyperliquid.ClientError else { return false }
                return error.reason == .timedOut && error.nonce == 7
            }
        }

        @Test func `an action without a signer throws before anything is sent`() async {
            let transport = FakeTransport()
            let order = OrderRequests.test(transport, signer: nil)
            let actions: [@Sendable () async throws -> Void] = [
                { _ = try await order.place([.limit(.buy, "BTC", price: 1, size: 1)]) },
                { _ = try await order.cancel([.init(.init(rawValue: 1), coin: "BTC")]) },
                { _ = try await order.modify([.init(.id(.init(rawValue: 1)), to: .limit(.buy, "BTC", price: 1, size: 1))]) },
                { try await order.clearScheduledCancel() },
            ]
            for action in actions {
                await #expect {
                    try await action()
                } throws: { error in
                    (error as? Hyperliquid.ClientError)?.reason == .missingSigner
                }
            }
            #expect(await transport.requests.isEmpty)
        }

        @Test func `a network failure carries the nonce the counter gave the action`() async {
            await #expect {
                try await OrderRequests.test(FailingTransport(), nonce: 42).clearScheduledCancel()
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.nonce == 42
            }
        }

        @Test(arguments: ["null", "not json", #"{"status":"err","response":{"unexpected":true}}"#])
        func `an answer the client can't read throws an unexpected response with the nonce`(body: String) async {
            let transport = FakeTransport(json: body)
            await #expect {
                try await OrderRequests.test(transport, nonce: 42).clearScheduledCancel()
            } throws: { error in
                guard let error = error as? HyperliquidError else { return false }
                return error.kind == .unexpectedResponse && error.nonce == 42 && error.body == Data(body.utf8)
            }
        }

        @Test func `a cancel status other than success is a failure with that text`() async throws {
            let transport = Self.transport(Self.meta, #"{"status":"ok","response":{"type":"cancel","data":{"statuses":["somethingNew"]}}}"#)
            let results = try await OrderRequests.test(transport).cancel([.init(.init(rawValue: 1), coin: "BTC")])
            #expect(results == [.init(error: "somethingNew")])
        }

        @Test func `an order on a spot coin throws before anything is sent`() async {
            let transport = FakeTransport()
            await #expect {
                try await OrderRequests.test(transport).place([.limit(.buy, "@107", price: 1, size: 1)])
            } throws: { error in
                (error as? Hyperliquid.ClientError)?.reason == .unsupportedMarket
            }
            #expect(await transport.requests.isEmpty)
        }
    }
}

/// Fails every request as a timeout would.
private struct FailingTransport: HTTPTransport {
    func send(_ request: TransportRequest) async throws -> TransportResponse {
        throw Hyperliquid.ClientError(.timedOut)
    }
}
