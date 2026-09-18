// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Maalumi",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Maalumi",
            targets: ["Maalumi"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Heiwanaramu/maalumi-core.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Maalumi",
            dependencies: [
                .product(name: "MaalumiCore", package: "maalumi-core")
            ],
            path: "Sources/Maalumi"
        )
    ]
)
