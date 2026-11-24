import Foundation
import HyperliquidKitCore
import Testing

extension HyperliquidKitCoreTests {
    @Suite("Errors")
    struct ErrorTests {
        @Test func `a Hyperliquid error describes its kind, status and message but not its body`() {
            let error = HyperliquidError(
                .httpStatus, message: "Failed to deserialize the JSON body into the target type", httpStatus: 422,
                body: Data(#"{"withdrawable":"1234.5"}"#.utf8)
            )
            #expect(
                error.description
                    == "Hyperliquid error httpStatus (HTTP 422): Failed to deserialize the JSON body into the target type"
            )
        }

        @Test func `the localized description is Hyperliquid's message when there is one`() {
            let error: any Error = HyperliquidError(.actionRejected, message: "Order must have minimum value of $10.")
            #expect(error.localizedDescription == "Order must have minimum value of $10.")
        }

        @Test(arguments: [
            (HyperliquidError.Kind.actionRejected, "Hyperliquid rejected the action"),
            (.httpStatus, "Hyperliquid answered with an HTTP error"),
            (.unexpectedResponse, "Hyperliquid's response has an unexpected shape"),
            (.init(rawValue: "somethingNew"), "Hyperliquid error somethingNew"),
        ])
        func `without a message the localized description says what failed`(kind: HyperliquidError.Kind, expected: String) {
            #expect(HyperliquidError(kind, message: "").errorDescription == expected)
        }

        @Test(arguments: [
            (HyperliquidError.Kind.actionRejected, "User or API Wallet 0x0459dea86a6d8a2bb4ef1bb2a1a2bd5ae44ece91 does not exist.", true),
            (.actionRejected, "Must deposit before performing actions. User: 0x0459dea86a6d8a2bb4ef1bb2a1a2bd5ae44ece91", true),
            (.actionRejected, "Order must have minimum value of $10.", false),
            (.httpStatus, "User or API Wallet 0x0459dea86a6d8a2bb4ef1bb2a1a2bd5ae44ece91 does not exist.", false),
        ])
        func `an unrecognized signer is told apart by Hyperliquid's message`(
            kind: HyperliquidError.Kind, message: String, expected: Bool
        ) {
            #expect(HyperliquidError(kind, message: message).isSignatureMismatch == expected)
        }

        @Test func `the nonce of a failed action is kept`() {
            #expect(HyperliquidError(.actionRejected, nonce: 1_732_400_000_000).nonce == 1_732_400_000_000)
        }

        @Test func `a client error describes its reason and message`() {
            let error = Hyperliquid.ClientError(.subscriptionRejected, message: "Error parsing JSON")
            #expect(error.description == "Hyperliquid client error: subscriptionRejected: Error parsing JSON")
            #expect(
                (error as any Error).localizedDescription
                    == "Hyperliquid rejected the stream subscription: Error parsing JSON"
            )
            #expect(Hyperliquid.ClientError(.missingSigner).errorDescription == "The client has no signer for an action")
        }
    }
}
