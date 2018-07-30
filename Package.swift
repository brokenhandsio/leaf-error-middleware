// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "LeafErrorMiddleware",
    products: [
        .library(name: "LeafErrorMiddleware", targets: ["LeafErrorMiddleware"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "LeafErrorMiddleware", dependencies: ["Vapor"]),
        .testTarget(name: "LeafErrorMiddlewareTests", dependencies: ["LeafErrorMiddleware"]),
    ]
)
