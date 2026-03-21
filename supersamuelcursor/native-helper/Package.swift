// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorVoiceHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CursorVoiceHelper", targets: ["CursorVoiceHelper"])
    ],
    targets: [
        .executableTarget(
            name: "CursorVoiceHelper",
            path: "Sources/CursorVoiceHelper"
        )
    ]
)
