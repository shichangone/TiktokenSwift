// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tiktoken",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(
            name: "Tiktoken",
            targets: ["Tiktoken"]),
        .executable(
            name: "TiktokenBenchmarks",
            targets: ["TiktokenBenchmarks"])
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "Tiktoken",
            dependencies: []),
        .executableTarget(
            name: "TiktokenBenchmarks",
            dependencies: ["Tiktoken"]),
        .testTarget(
            name: "TiktokenTests",
            dependencies: [
                "Tiktoken",
                .product(name: "SwiftCheck", package: "SwiftCheck")
            ])
    ]
)
