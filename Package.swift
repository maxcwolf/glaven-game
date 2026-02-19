// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GlavenGame",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GlavenGame", targets: ["GlavenGame"])
    ],
    targets: [
        .executableTarget(
            name: "GlavenGame",
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
        )
    ]
)
