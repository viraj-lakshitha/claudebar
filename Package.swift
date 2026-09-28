// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeBar", targets: ["ClaudeBar"]),
    ],
    targets: [
        .target(name: "ClaudeBarCore"),
        .executableTarget(
            name: "ClaudeBar",
            dependencies: ["ClaudeBarCore"]
        ),
        .testTarget(
            name: "ClaudeBarCoreTests",
            dependencies: ["ClaudeBarCore"]
        ),
    ]
)
