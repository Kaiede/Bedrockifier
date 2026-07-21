// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "bedrockifier",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "bedrockifier",
            targets: ["bedrockifier"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.14.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/Kaiede/PTYKit.git", branch: "master"),
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.16.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", from: "0.65.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
    ],
    targets: [
        .executableTarget(
            name: "bedrockifier",
            dependencies: [
                "BedrockifierLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ConsoleKitTerminal", package: "console-kit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "PTYKit", package: "PTYKit")
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .target(
            name: "BedrockifierLib",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "PTYKit", package: "PTYKit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "BedrockifierLibTests",
            dependencies: [
                "BedrockifierLib",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
    ]
)
