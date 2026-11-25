import Foundation
import HyperliquidKit

/// The code of the documentation's examples, in the DocC articles and the README, compiled and never
/// run: they call Hyperliquid, and some place orders. A function may add lines that use its values.
enum DocumentationExamples {
    // MARK: Landing page and README

    static func landingPage() async throws {
        let client = Hyperliquid.Client()
        let mids = try await client.market.mids()
        _ = mids
    }

    static func quickStart(account: Hyperliquid.Address, apiWalletKey: String) async throws {
        // The API wallet's key comes from the Keychain or the environment, never from a literal.
        let signer = try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey)
        let client = Hyperliquid.Client(account: account, signer: signer)

        let mids = try await client.market.mids()
        print(mids["BTC"] ?? 0)

        for try await book in client.stream.orderBook("BTC") {
            print(book.bids.first?.price ?? 0, book.asks.first?.price ?? 0)
        }
    }

    // MARK: Getting started

    static func createClients(account: Hyperliquid.Address, apiWalletKey: String) throws {
        let signer = try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey)
        let client = Hyperliquid.Client(account: account, signer: signer, configuration: .init(timeout: .seconds(10)))

        // Market data and market streams need neither an account nor a signer.
        let publicClient = Hyperliquid.Client()

        // Testnet trades with test funds: the account needs them, and the API wallet approved, on testnet.
        let testnetClient = Hyperliquid.Client(account: account, signer: signer, configuration: .init(network: .testnet))

        _ = (client, publicClient, testnetClient)
    }

    static func readMids(client: Hyperliquid.Client) async throws {
        let mids = try await client.market.mids()
        print(mids["BTC"] ?? 0)
    }

    // swift-format-ignore: NeverForceUnwrap
    // The guide shows a decimal built from a fixed string, which always parses.
    static func placeAndCancelOrder(client: Hyperliquid.Client) async throws {
        guard let mid = try await client.market.mids()["BTC"],
            let btc = try await client.market.perpetuals().first(where: { $0.coin == "BTC" })
        else { return }

        // A buy 10% under the mid price rests in the book. BTC's price in whole dollars is always
        // valid, and an order must be worth at least $10.
        var exactPrice = mid * Decimal(string: "0.9")!
        var price = Decimal()
        NSDecimalRound(&price, &exactPrice, 0, .down)
        var exactSize = Decimal(11) / price
        var size = Decimal()
        NSDecimalRound(&size, &exactSize, btc.sizeDecimals, .up)

        let placed = try await client.order.place([
            .limit(.buy, "BTC", price: price, size: size, timeInForce: .addLiquidityOnly)
        ])
        guard let id = placed.first?.orderID else {
            print("Not placed:", placed.first?.error ?? "")
            return
        }
        let canceled = try await client.order.cancel([.init(id, coin: "BTC")])
        print(canceled.first?.isCanceled == true ? "Canceled" : canceled.first?.error ?? "")
    }

    static func openAndClose(client: Hyperliquid.Client, size: Decimal) async throws {
        // A market buy pays at most about the mid price plus 5%, unless you pass another slippage.
        let opened = try await client.order.place([.market(.buy, "BTC", size: size)])
        guard let filled = opened.first?.filledSize, filled > 0 else { return }

        // Sells what was bought with a reduce-only market order.
        let closed = try await client.order.close("BTC", size: filled)
        print(closed.first?.averagePrice ?? 0)
    }

    static func streamBook(client: Hyperliquid.Client) async throws {
        for try await book in client.stream.orderBook("BTC") {
            print(book.bids.first?.price ?? 0, book.asks.first?.price ?? 0)
        }
    }

    static func streamFills(client: Hyperliquid.Client) async throws {
        for try await batch in client.stream.fills() where !batch.isSnapshot {
            for fill in batch.elements {
                print(fill.coin, fill.side, fill.price, fill.size)
            }
        }
    }

    static func handleErrors(client: Hyperliquid.Client, order: Hyperliquid.OrderRequest) async throws {
        do {
            // A rejected order doesn't throw: its result says why.
            for result in try await client.order.place([order]) where result.status == .rejected {
                print("Hyperliquid rejected the order:", result.error ?? "")
            }
        } catch let error as HyperliquidError where error.kind == .actionRejected {
            print("Hyperliquid rejected the action:", error.message ?? "")
        } catch {
            // Another failure after sending, such as a timeout, can leave the outcome unknown. Spending
            // the nonce stops the action if it hasn't executed.
            print(error.localizedDescription)
            if let nonce = (error as? Hyperliquid.ClientError)?.nonce ?? (error as? HyperliquidError)?.nonce {
                try await client.order.invalidate(nonce: nonce)
            }
        }
    }

    // MARK: API wallets

    static func tradeForAVault(vault: Hyperliquid.Address, apiWalletKey: String) throws {
        let client = Hyperliquid.Client(
            signer: try Hyperliquid.PrivateKeySigner(hexKey: apiWalletKey), configuration: .init(vaultAddress: vault)
        )
        _ = client
    }
}
