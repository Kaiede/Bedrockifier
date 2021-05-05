// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BedrockifierCLI",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
            // The external product of our package is an importable
            // library that has the same name as the package itself:
            .executable(
                name: "BedrockifierCLI",
                targets: ["BedrockifierCLI"]
            )
        ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/vapor/console-kit.git", .upToNextMinor(from: "4.2.5")),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/Kaiede/PTYKit.git", .branch("master")),
        //.package(path: "../PTYKit")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "BedrockifierCLI",
            dependencies: ["Bedrockifier"]
        ),
        .target(
            name: "Bedrockifier",
            dependencies: [
                .product(name: "ConsoleKit", package: "console-kit"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "PTYKit", package: "PTYKit")
            ]),
        .testTarget(
            name: "BedrockifierTests",
            dependencies: ["Bedrockifier"]),
    ]
)
