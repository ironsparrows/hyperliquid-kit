@testable import HyperliquidKit

/// The key and actions the signing suites and the fakes sign with. Hyperliquid's Python SDK
/// publishes its test key and these actions in `tests/signing_test.py`. The key signs no real
/// wallet's actions and is the only key in this repository.
enum SigningVectors {
    static let pythonTestKey = "0x0123456789012345678901234567890123456789012345678901234567890123"
    // The key is valid, so building the signer can't fail.
    static let pythonTestSigner = try! Hyperliquid.PrivateKeySigner(hexKey: pythonTestKey)

    enum Action: String, CaseIterable, Sendable {
        case dummy, order, orderWithClientID, vault, trigger, scheduleCancel, scheduleCancelAtTime
        case createSubAccount, subAccountTransfer
    }

    static func l1Action(_ action: Action) -> L1Action {
        let dummy: ActionValue = ["type": "dummy", "num": 100_000_000_000]
        func order(_ type: ActionValue, clientID: String? = nil) -> ActionValue {
            var fields: [ActionValue.Entry] = [
                .init(key: "a", value: 1), .init(key: "b", value: true), .init(key: "p", value: "100"),
                .init(key: "s", value: "100"), .init(key: "r", value: false), .init(key: "t", value: type),
            ]
            if let clientID { fields.append(.init(key: "c", value: .string(clientID))) }
            return ["type": "order", "orders": [.map(fields)], "grouping": "na"]
        }
        let value: ActionValue
        var vault: Hyperliquid.Address?
        switch action {
        case .dummy:
            value = dummy
        case .order:
            value = order(["limit": ["tif": "Gtc"]])
        case .orderWithClientID:
            value = order(["limit": ["tif": "Gtc"]], clientID: "0x00000000000000000000000000000001")
        case .vault:
            value = dummy
            vault = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"
        case .trigger:
            value = order(["trigger": ["isMarket": true, "triggerPx": "103", "tpsl": "sl"]])
        case .scheduleCancel:
            value = ["type": "scheduleCancel"]
        case .scheduleCancelAtTime:
            value = ["type": "scheduleCancel", "time": 123_456_789]
        case .createSubAccount:
            value = ["type": "createSubAccount", "name": "example"]
        case .subAccountTransfer:
            value = [
                "type": "subAccountTransfer", "subAccountUser": "0x1d9470d4b963f552e6f671a81619d395877bf409",
                "isDeposit": true, "usd": 10,
            ]
        }
        return L1Action(action: value, nonce: 0, vault: vault, expiresAfter: nil)
    }
}
