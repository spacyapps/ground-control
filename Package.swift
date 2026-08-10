// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SkinTerminal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SkinTerminal", targets: ["SkinTerminal"])
    ],
    dependencies: [
        // Lint runs as a build-tool plugin so violations show inline in Xcode.
        .package(url: "https://github.com/realm/SwiftLint.git", from: "0.55.0")
    ],
    targets: [
        .executableTarget(
            name: "SkinTerminal",
            path: "Sources/SkinTerminal",
            resources: [
                .process("Resources")
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        ),
        .testTarget(
            name: "SkinTerminalTests",
            dependencies: ["SkinTerminal"],
            path: "Tests/SkinTerminalTests"
        )
    ]
)
