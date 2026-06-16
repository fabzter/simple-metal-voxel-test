// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VoxelGame",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VoxelGame",
            targets: ["VoxelGame"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VoxelGame",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
