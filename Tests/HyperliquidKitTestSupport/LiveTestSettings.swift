import Foundation
package import HyperliquidKitCore
package import Testing

// Live tests run when an API wallet's key and the account's address are set, in the environment
// (`HYPERLIQUID_AGENT_KEY`, `HYPERLIQUID_ACCOUNT`) or in `LocalLiveTestSettings.swift` beside this
// file: a gitignored file only a contributor creates, so Xcode runs need no environment variables.
// Without that file, the protocol's defaults below are empty and the package still builds.

/// Whether live tests run: an API wallet's key and the account's address are set.
package var areLiveTestsEnabled: Bool { LiveTestSettings.values != nil }

/// The values live tests read.
package enum LiveTestSettings {
    /// The account's address and the API wallet's key: from the environment when either is set
    /// there, else from the local file; `nil` unless both are set and the address is valid.
    package static let values: (account: Hyperliquid.Address, agentKey: String)? = {
        let environment = ProcessInfo.processInfo.environment
        let environmentAccount = environment["HYPERLIQUID_ACCOUNT"] ?? ""
        let environmentKey = environment["HYPERLIQUID_AGENT_KEY"] ?? ""
        if !environmentAccount.isEmpty || !environmentKey.isEmpty {
            guard let account = try? Hyperliquid.Address(environmentAccount), !environmentKey.isEmpty else { return nil }
            return (account, environmentKey)
        }
        if let account = try? Hyperliquid.Address(LocalLiveTestSettings.account),
            !LocalLiveTestSettings.agentKey.isEmpty
        {
            return (account, LocalLiveTestSettings.agentKey)
        }
        return nil
    }()
}

/// What the local file sets. Its defaults are empty.
protocol LocalLiveTestValues {
    static var account: String { get }
    static var agentKey: String { get }
}

extension LocalLiveTestValues {
    static var account: String { "" }
    static var agentKey: String { "" }
}

/// The local settings. `LocalLiveTestSettings.swift`, when present, gives this type its own
/// `static let account` and `static let agentKey`, which replace the empty defaults.
enum LocalLiveTestSettings: LocalLiveTestValues {}

extension Tag {
    /// Tests that call Hyperliquid's live servers.
    @Tag package static var live: Self
}
