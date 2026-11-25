import Foundation
import Testing
@testable import HyperliquidKit

extension HyperliquidKitTests {
    @Suite("Typed data")
    struct TypedDataTests {
        @Test func `an action's request carries the same message as EIP-712 JSON`() throws {
            let action = L1Action(action: ["type": "scheduleCancel"], nonce: 0, vault: nil, expiresAfter: nil)
            let request = action.signingRequest(on: .mainnet)
            let connectionID = hexadecimal(action.connectionID)
            #expect(request.digest.count == 32)
            #expect(
                request.typedData
                    == #"{"domain":{"chainId":1337,"name":"Exchange","verifyingContract":"0x0000000000000000000000000000000000000000","version":"1"},"types":{"Agent":[{"name":"source","type":"string"},{"name":"connectionId","type":"bytes32"}],"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}]},"primaryType":"Agent","message":{"source":"a","connectionId":""#
                    + connectionID + #""}}"#
            )
        }

        @Test func `the network names the request's source`() throws {
            let action = L1Action(action: ["type": "scheduleCancel"], nonce: 0, vault: nil, expiresAfter: nil)
            #expect(action.signingRequest(on: .testnet).typedData.contains(#""source":"b""#))
            #expect(action.signingRequest(on: .mainnet).digest != action.signingRequest(on: .testnet).digest)
        }
    }
}
