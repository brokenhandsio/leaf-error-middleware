// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "LeafErrorMiddleware",
    platforms: [
       .macOS(.v12),
    ],
    products: [
        .library(name: "LeafErrorMiddleware", targets: ["LeafErrorMiddleware"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.50.0"),
    ],
    targets: [
        .target(name: "LeafErrorMiddleware", dependencies: [
            .product(name: "Vapor", package: "vapor"),
        ]),
        .testTarget(name: "LeafErrorMiddlewareTests", dependencies: ["LeafErrorMiddleware"]),
    ]
)
