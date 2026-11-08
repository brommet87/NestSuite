// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

/// NestKit holds everything that is not the app shell, so it can be unit-tested with `swift test`
/// without building or signing an application bundle.
///
/// - `NestCore`: pure domain model (configurations, VM bundles, state machine). No Apple
///   virtualization APIs, no UI. Fully testable.
/// - `NestSpec`: the declarative `Nestfile.yml` format (parsing, validation, mapping to NestCore).
/// - `NestVirtualization`: the adapter between `NestCore` and `Virtualization.framework`.
/// - `NestDesign`: design tokens and reusable SwiftUI components.
/// - `NestCLI` + `nestctl`: the command-line interface (library for testability, thin executable).
let package = Package(
    name: "NestKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NestCore", targets: ["NestCore"]),
        .library(name: "NestSpec", targets: ["NestSpec"]),
        .library(name: "NestVirtualization", targets: ["NestVirtualization"]),
        .library(name: "NestImages", targets: ["NestImages"]),
        .library(name: "NestDesign", targets: ["NestDesign"]),
        .executable(name: "nestctl", targets: ["nestctl"]),
    ],
    dependencies: [
        // Both are GPL-compatible (MIT, Apache-2.0) and not virtualization products (see ADR 0006).
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    ],
    targets: [
        .target(name: "NestCore"),
        .target(name: "NestSpec", dependencies: ["NestCore", .product(name: "Yams", package: "Yams")]),
        .target(name: "NestVirtualization", dependencies: ["NestCore"]),
        .target(name: "NestImages", dependencies: ["NestCore"]),
        .target(name: "NestDesign", dependencies: ["NestCore"], resources: [.process("Resources")]),
        .target(
            name: "NestCLI",
            dependencies: [
                "NestCore", "NestSpec", "NestVirtualization", "NestImages",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "nestctl",
            dependencies: ["NestCLI", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(name: "NestCoreTests", dependencies: ["NestCore"]),
        .testTarget(name: "NestSpecTests", dependencies: ["NestSpec"]),
        .testTarget(name: "NestVirtualizationTests", dependencies: ["NestVirtualization"]),
        .testTarget(name: "NestCLITests", dependencies: ["NestCLI"]),
        .testTarget(name: "NestImagesTests", dependencies: ["NestImages"]),
    ],
    swiftLanguageModes: [.v6]
)
