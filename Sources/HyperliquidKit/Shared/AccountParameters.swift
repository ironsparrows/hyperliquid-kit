import HyperliquidKitCore

/// The address an account read is for: the one given, else the client's account.
///
/// - Throws: `missingAccount` when there is neither, before anything is sent.
func resolveAccount(_ user: Hyperliquid.Address?, default account: Hyperliquid.Address?) throws(Hyperliquid.ClientError)
    -> Hyperliquid.Address
{
    guard let address = user ?? account else {
        throw Hyperliquid.ClientError(.missingAccount)
    }
    return address
}

/// `user`, as account reads take it.
func userParameter(_ user: Hyperliquid.Address) -> ActionValue.Entry {
    .init(key: "user", value: .string(user.description))
}
