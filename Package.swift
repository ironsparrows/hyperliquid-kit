// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "hyperliquid-kit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "HyperliquidKit", targets: ["HyperliquidKit"]),
        .library(name: "HyperliquidKitCore", targets: ["HyperliquidKitCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", .upToNextMinor(from: "0.25.1")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMinor(from: "1.10.0")),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.37.1"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.16.2"),
    ],
    targets: [
        .target(
            name: "HyperliquidKitCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "HyperliquidKit",
            dependencies: [
                "HyperliquidKitCore",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "WebSocketKit", package: "websocket-kit"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "HyperliquidKitTestSupport",
            dependencies: ["HyperliquidKitCore"],
            path: "Tests/HyperliquidKitTestSupport",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HyperliquidKitCoreTests",
            dependencies: ["HyperliquidKitCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HyperliquidKitTests",
            dependencies: [
                "HyperliquidKit",
                "HyperliquidKitTestSupport",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
