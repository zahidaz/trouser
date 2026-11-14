// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trouser",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TrouserBridge", linkerSettings: [.linkedFramework("WebKit")]),
        .executableTarget(name: "Trouser", dependencies: ["TrouserBridge"]),
        .testTarget(name: "TrouserTests", dependencies: ["Trouser"])
    ]
)
