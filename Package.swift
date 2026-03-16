// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Desktopflow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DesktopflowCore", targets: ["DesktopflowCore"]),
        .library(name: "DesktopflowPlatform", targets: ["DesktopflowPlatform"]),
        .library(name: "DesktopflowStorage", targets: ["DesktopflowStorage"]),
        .executable(name: "DesktopflowApp", targets: ["DesktopflowApp"]),
        .executable(name: "DesktopflowChecks", targets: ["DesktopflowChecks"])
    ],
    targets: [
        .target(
            name: "DesktopflowCore"
        ),
        .target(
            name: "DesktopflowPlatform",
            dependencies: ["DesktopflowCore"]
        ),
        .target(
            name: "DesktopflowStorage",
            dependencies: ["DesktopflowCore"]
        ),
        .executableTarget(
            name: "DesktopflowApp",
            dependencies: ["DesktopflowCore", "DesktopflowPlatform", "DesktopflowStorage"]
        ),
        .executableTarget(
            name: "DesktopflowChecks",
            dependencies: ["DesktopflowCore"]
        )
    ]
)
