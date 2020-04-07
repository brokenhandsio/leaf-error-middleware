// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "leaf-error-middleware",
    platforms: [
       .macOS(.v10_15),
    ],
    products: [
        .library(name: "LeafErrorMiddleware", targets: ["LeafErrorMiddleware"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0-rc"),
    ],
    targets: [
        .target(name: "LeafErrorMiddleware", dependencies: [
            .product(name: "Vapor", package: "vapor"),
        ]),
        .testTarget(name: "LeafErrorMiddlewareTests", dependencies: ["LeafErrorMiddleware"]),
    ]
)
