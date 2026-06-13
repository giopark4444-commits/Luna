// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Luna",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Luna",
            path: "Sources/Luna"
        )
    ]
)
