// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Authon",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(name: "Authon", targets: ["Authon"]),
    ],
    targets: [
        .target(name: "Authon", path: "Sources/Authon"),
    ]
)
