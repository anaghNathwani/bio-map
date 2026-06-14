// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BirdMap",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "BirdMap",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        )
    ]
)
