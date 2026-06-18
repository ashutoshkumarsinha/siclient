// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SICLient",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "SICLientCore", targets: ["SICLientCore"]),
        .executable(name: "siclient", targets: ["siclient"]),
    ],
    targets: [
        .target(
            name: "SICLientCore",
            path: "Sources/SICLientCore"
        ),
        .executableTarget(
            name: "siclient",
            dependencies: ["SICLientCore"],
            path: "Sources/siclient"
        ),
        .testTarget(
            name: "SICLientCoreTests",
            dependencies: ["SICLientCore"],
            path: "Tests/SICLientCoreTests"
        ),
    ]
)
