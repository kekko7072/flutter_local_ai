// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_local_ai",
    platforms: [
        .iOS("13.0"),
        .macOS("12.0")
    ],
    products: [
        .library(
            name: "flutter-local-ai",
            targets: ["flutter_local_ai"]
        ),
    ],
    targets: [
        .target(
            name: "flutter_local_ai",
            path: "Classes"
        ),
    ]
)
