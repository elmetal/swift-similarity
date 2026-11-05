// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-similarity",
    platforms: [.macOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-similarity",
            targets: ["swift-similarity"]),
        .executable(
            name: "swift-similarity-cli",
            targets: ["swift-similarity-cli"]),
        // `swift package similarity`: runs `swift-similarity-cli scan` on the package's sources.
        .plugin(
            name: "SimilarityPlugin",
            targets: ["SimilarityPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", 
                 from: "601.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", 
                 from: "1.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "swift-similarity",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]),
        .executableTarget(
            name: "swift-similarity-cli",
            dependencies: [
                "swift-similarity",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .plugin(
            name: "SimilarityPlugin",
            capability: .command(
                intent: .custom(
                    verb: "similarity",
                    description: "Find similar Swift declarations in the package's source targets"
                )
            ),
            dependencies: ["swift-similarity-cli"]
        ),
        .testTarget(
            name: "swift-similarityTests",
            dependencies: ["swift-similarity"]
        ),
    ]
)
