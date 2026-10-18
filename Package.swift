// swift-tools-version: 6.2
import PackageDescription

// Everything here is AppKit-free: SwiftUI and Foundation only. The macOS
// shell and the widget extension live under Apps/ and are built by the
// XcodeGen project (project.yml).
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "topophany-bar",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TopophanyKit", targets: ["TopophanyKit"]),
        .library(name: "TopophanyEngine", targets: ["TopophanyEngine"]),
        .library(name: "TopophanySections", targets: ["TopophanySections"]),
        .library(name: "TopophanyThemes", targets: ["TopophanyThemes"]),
        .library(name: "TopophanyWidgets", targets: ["TopophanyWidgets"]),
        .library(name: "LocalReadings", targets: ["LocalReadings"]),
    ],
    targets: [
        .target(name: "TopophanyKit", swiftSettings: strict),
        .target(
            name: "TopophanyEngine",
            dependencies: ["TopophanyKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
        .target(name: "LocalReadings", swiftSettings: strict),
        .target(
            name: "TopophanySections",
            dependencies: ["TopophanyKit", "LocalReadings"],
            resources: [.process("Resources")],
            swiftSettings: strict
        ),
        .target(
            name: "TopophanyThemes",
            dependencies: ["TopophanyKit", "TopophanySections"],
            resources: [.process("Resources")],
            swiftSettings: strict
        ),
        .target(
            name: "TopophanyWidgets",
            dependencies: ["TopophanyKit", "TopophanySections", "TopophanyThemes"],
            swiftSettings: strict
        ),

        .testTarget(name: "TopophanyKitTests", dependencies: ["TopophanyKit"], swiftSettings: strict),
        .testTarget(
            name: "TopophanyEngineTests",
            dependencies: ["TopophanyEngine", "TopophanyKit"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "TopophanySectionsTests",
            dependencies: ["TopophanySections", "TopophanyEngine", "TopophanyKit"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "TopophanyThemesTests",
            dependencies: ["TopophanyThemes", "TopophanySections", "TopophanyEngine", "TopophanyKit", "LocalReadings"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "TopophanyWidgetsTests",
            dependencies: ["TopophanyWidgets", "TopophanyThemes", "TopophanySections", "TopophanyEngine", "TopophanyKit"],
            swiftSettings: strict
        ),
        .testTarget(name: "LocalReadingsTests", dependencies: ["LocalReadings"], swiftSettings: strict),
    ]
)
