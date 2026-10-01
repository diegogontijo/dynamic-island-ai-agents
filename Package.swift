// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentIsland",
            path: "Sources/AgentIsland"
        )
    ],
    swiftLanguageModes: [.v5]
)
