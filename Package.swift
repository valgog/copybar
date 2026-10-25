// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CopyBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CopyBarCore"),
        .executableTarget(name: "CopyBar", dependencies: ["CopyBarCore"]),
        .testTarget(name: "CopyBarCoreTests", dependencies: ["CopyBarCore"]),
    ]
)
