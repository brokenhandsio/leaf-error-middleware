import PackageDescription

let package = Package(
    name: "LeafErrorMiddleware",
    dependencies: [
        .Package(url: "https://github.com/vapor/vapor.git", .branch("master") ),
    ]
)
