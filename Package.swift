// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BedrockifierCLI",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/vapor/console-kit.git", .upToNextMinor(from: "4.2.5")),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/Kaiede/PtyKit.git", .branch("master"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "BedrockifierCLI",
            dependencies: [
                .product(name: "ConsoleKit", package: "console-kit"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "PtyKit", package: "PtyKit")
            ]),
        .testTarget(
            name: "BedrockifierCLITests",
            dependencies: ["BedrockifierCLI"]),
    ]
)
