// swift-tools-version: 5.9
// Package.swift for Flutter plugin flutter_local_ai
// This file is used when developing the plugin with Swift Package Manager
import PackageDescription

let package = Package(
    name: "flutter_local_ai",
    platforms: [
        .iOS(26.0)
    ],
    products: [
        .library(
            name: "flutter_local_ai",
            targets: ["flutter_local_ai"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_local_ai",
            dependencies: [],
            path: "Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
                .define("DEFINES_MODULE", to: "YES"),
            ],
            swiftSettings: [
                .define("DEFINES_MODULE"),
            ]
        ),
    ]
)
