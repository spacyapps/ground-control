// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-or-later
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
    name: "GroundControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GroundControl", targets: ["GroundControl"]),
        // A terminal preview for `matrix.shape` formulas — reuses MatrixKit so
        // what it draws is exactly what the panel draws. See Sources/matrix-preview.
        .executable(name: "matrix-preview", targets: ["matrix-preview"])
    ],
    targets: [
        // The analyser's formula engine: Foundation only, no AppKit, no app
        // state. Its own target so the preview tool and the tests can use it
        // without pulling in the whole app.
        .target(
            name: "MatrixKit",
            path: "Sources/MatrixKit"
        ),
        .executableTarget(
            name: "GroundControl",
            dependencies: ["MatrixKit"],
            path: "Sources/GroundControl",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "matrix-preview",
            dependencies: ["MatrixKit"],
            path: "Sources/matrix-preview"
        ),
        .testTarget(
            name: "GroundControlTests",
            dependencies: ["GroundControl", "MatrixKit"],
            path: "Tests/GroundControlTests"
        )
    ]
)
