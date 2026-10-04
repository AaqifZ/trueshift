// swift-tools-version: 5.9
// Trueshift: Circadian Display Control CLI for macOS

import PackageDescription

let package = Package(
    name: "Trueshift",
    platforms: [
        .macOS(.v14)  // macOS 14 for menu bar app
    ],
    products: [
        .executable(name: "trueshift", targets: ["trueshift"]),
        .executable(name: "TrueshiftBar", targets: ["TrueshiftBar"]),
    ],
    dependencies: [
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Sunrise/sunset calculation
        .package(url: "https://github.com/ceeK/Solar.git", from: "3.0.0"),
        // YAML config parsing
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        // ObjC bridge for CoreBrightness private framework (Night Shift API)
        .target(
            name: "CoreBrightnessBridge",
            dependencies: [],
            path: "Sources/CoreBrightnessBridge",
            publicHeadersPath: "include"
        ),
        // Shared library with core functionality
        .target(
            name: "TrueshiftCore",
            dependencies: [
                "Solar",
                "Yams",
                "CoreBrightnessBridge",
            ],
            path: "Sources/TrueshiftCore"
        ),
        // CLI tool
        .executableTarget(
            name: "trueshift",
            dependencies: [
                "TrueshiftCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Trueshift"
        ),
        // Menu bar app
        .executableTarget(
            name: "TrueshiftBar",
            dependencies: [
                "TrueshiftCore",
            ],
            path: "Sources/TrueshiftBar"
        ),
        // Tests for TrueshiftCore
        .testTarget(
            name: "TrueshiftCoreTests",
            dependencies: ["TrueshiftCore"],
            path: "Tests/TrueshiftCoreTests"
        ),
    ]
)
