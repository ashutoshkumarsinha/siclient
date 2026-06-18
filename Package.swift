// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SICLient",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "SICLientCore", targets: ["SICLientCore"]),
        .library(name: "SICLientGUI", targets: ["SICLientGUI"]),
        .executable(name: "siclient", targets: ["siclient"]),
        .executable(name: "siclient-gui", targets: ["siclient-gui"]),
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
        .target(
            name: "SICLientGUI",
            dependencies: ["SICLientCore"],
            path: "Sources/SICLientGUI"
        ),
        .executableTarget(
            name: "siclient-gui",
            dependencies: ["SICLientGUI"],
            path: "Sources/siclient-gui"
        ),
        .testTarget(
            name: "SICLientCoreTests",
            dependencies: ["SICLientCore"],
            path: "Tests/SICLientCoreTests"
        ),
        .testTarget(
            name: "SICLientGUITests",
            dependencies: ["SICLientGUI", "SICLientCore"],
            path: "Tests/SICLientGUITests"
        ),
    ]
)
