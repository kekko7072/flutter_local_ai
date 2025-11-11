// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_local_ai",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "flutter_local_ai",
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
