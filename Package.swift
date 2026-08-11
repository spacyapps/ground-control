// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Walter Mak
import PackageDescription

// No third-party dependencies, by design.
//
// SwiftLint used to be declared here as a build-tool plugin. That pulled in
// nine transitive packages — swift-syntax among them — so a clean clone spent
// minutes building a linter before compiling a line of the app, and CI paid
// for it twice by also installing swiftlint from Homebrew to run standalone.
//
// Linting now runs from the standalone binary (`swiftlint --strict`), locally
// and in CI. Nothing third-party ends up in the shipped app.
let package = Package(
    name: "SkinTerminal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SkinTerminal", targets: ["SkinTerminal"])
    ],
    targets: [
        .executableTarget(
            name: "SkinTerminal",
            path: "Sources/SkinTerminal",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SkinTerminalTests",
            dependencies: ["SkinTerminal"],
            path: "Tests/SkinTerminalTests"
        )
    ]
)
