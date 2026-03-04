// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperSamuel",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SuperSamuel", targets: ["SuperSamuelApp"])
    ],
    targets: [
        .executableTarget(
            name: "SuperSamuelApp",
            path: "Sources/SuperSamuelApp"
        )
    ]
)
