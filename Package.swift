// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StylusDeck",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VolumeCore",
            targets: ["VolumeCore"]
        ),
        .executable(
            name: "StylusDeck",
            targets: ["StylusDeck"]
        ),
        .executable(
            name: "VolumeBridge",
            targets: ["VolumeBridge"]
        ),
        .executable(
            name: "EqBridge",
            targets: ["EqBridge"]
        ),
    ],
    targets: [
        .target(
            name: "VolumeCore"
        ),
        .executableTarget(
            name: "StylusDeck",
            dependencies: ["VolumeCore"],
            path: "Sources/VolumeTablet"
        ),
        .executableTarget(
            name: "VolumeBridge",
            dependencies: ["VolumeCore"]
        ),
        .executableTarget(
            name: "EqBridge",
            dependencies: ["VolumeCore"]
        ),
    ]
)
