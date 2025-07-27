// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-similarity",
    platforms: [.macOS(.v10_15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-similarity",
            targets: ["swift-similarity"]),
        .executable(
            name: "swift-similarity-cli",
            targets: ["swift-similarity-cli"]),
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
        .testTarget(
            name: "swift-similarityTests",
            dependencies: ["swift-similarity"]
        ),
    ]
)
