// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastIRL",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "FastIRL",
            dependencies: ["Starscream"]
        )
    ]
)
