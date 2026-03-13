// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GlavenGame",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GlavenGame", targets: ["GlavenGame"]),
        .library(name: "GlavenGameLib", targets: ["GlavenGameLib"])
    ],
    targets: [
        // Library target containing all game logic (testable)
        .target(
            name: "GlavenGameLib",
            path: "GlavenGame",
            exclude: ["Previews", "Assets.xcassets"],
            resources: [
                .copy("Resources/EditionData"),
                .copy("Resources/Images"),
                .copy("Resources/Sounds"),
                .copy("Resources/Fonts"),
                .copy("Resources/ScenarioMaps"),
                .copy("Resources/CardImages")
            ]
        ),
        // Executable target — thin wrapper that launches the app
        .executableTarget(
            name: "GlavenGame",
            dependencies: ["GlavenGameLib"],
            path: "GlavenGameApp"
        ),
        .testTarget(
            name: "GlavenGameTests",
            dependencies: ["GlavenGameLib"],
            path: "Tests"
        )
    ]
)
