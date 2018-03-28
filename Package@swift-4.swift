// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "LeafErrorMiddleware",
    products: [
        .library(name: "LeafErrorMiddleware", targets: ["LeafErrorMiddleware"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .branch("master") ),
    ],
    targets: [
        .target(name: "LeafErrorMiddleware", dependencies: ["Vapor"]),
        .testTarget(name: "LeafErrorMiddlewareTests", dependencies: ["LeafErrorMiddleware"]),
    ]
)
