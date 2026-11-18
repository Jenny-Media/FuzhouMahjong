// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuzhouCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FuzhouCore", targets: ["FuzhouCore"]),
        .library(name: "FuzhouNearby", targets: ["FuzhouNearby"]),
        .library(name: "FuzhouAccess", targets: ["FuzhouAccess"]),
    ],
    targets: [
        .target(name: "FuzhouCore"),
        .target(name: "FuzhouAccess"),
        .target(name: "FuzhouNearby", dependencies: ["FuzhouCore"]),
        .testTarget(name: "FuzhouCoreTests", dependencies: ["FuzhouCore"]),
        .testTarget(name: "FuzhouAccessTests", dependencies: ["FuzhouAccess"]),
        .testTarget(name: "FuzhouNearbyTests", dependencies: ["FuzhouNearby", "FuzhouCore"]),
    ]
)
