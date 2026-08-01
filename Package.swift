// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundPlayback",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SoundPlayback", targets: ["SoundPlayback"]),
    ],
    targets: [
        .executableTarget(
            name: "SoundPlayback",
            path: "Sources/SoundPlayback"
        ),
    ]
)
