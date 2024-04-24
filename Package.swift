// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bedrockifier",
    platforms: [
        .macOS(.v13)
    ],
    products: [
            // The external product of our package is an importable
            // library that has the same name as the package itself:
            .executable(
                name: "bedrockifier-tool",
                targets: ["Tool"]
            ),
            .executable(
                name: "bedrockifierd",
                targets: ["Service"]
            )
        ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.1.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/Kaiede/PTYKit.git", branch: "master"),
        .package(url: "https://github.com/swift-server/swift-backtrace.git", from: "1.3.3"),
        .package(url: "https://github.com/vapor/console-kit.git", .upToNextMinor(from: "4.2.5")),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "Tool",
            dependencies: [
                "Bedrockifier",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ConsoleKit", package: "console-kit")
            ]
        ),
        .executableTarget(
            name: "Service",
            dependencies: [
                "Bedrockifier",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Backtrace", package: "swift-backtrace")
            ]
        ),
        .target(
            name: "Bedrockifier",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "PTYKit", package: "PTYKit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]),
        .testTarget(
            name: "BedrockifierTests",
            dependencies: ["Bedrockifier"]),
    ]
)
