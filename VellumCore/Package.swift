// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VellumCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VellumCore", targets: ["VellumCore"]),
    ],
    targets: [
        .target(name: "VellumCore"),
        .testTarget(name: "VellumCoreTests", dependencies: ["VellumCore"]),
    ],
    swiftLanguageModes: [.v6]
)
