// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuraTV",
    platforms: [
        .tvOS(.v18)
    ],
    products: [
        .library(
            name: "AuraTV",
            targets: ["AuraTV"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/kingslay/KSPlayer.git", from: "2.3.0")
    ],
    targets: [
        .target(
            name: "AuraTV",
            dependencies: [
                .product(name: "KSPlayer", package: "KSPlayer")
            ],
            path: "AuraTV"
        ),
    ]
)
