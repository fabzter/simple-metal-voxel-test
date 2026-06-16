// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "VoxelGame",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "VoxelGameKit",
            targets: ["VoxelGameKit"]
        ),
        .executable(
            name: "VoxelGame",
            targets: ["VoxelGame"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "VoxelGame",
            dependencies: ["VoxelGameKit"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .target(
            name: "VoxelGameKit",
            resources: [
                .copy("Shaders")
            ],
            plugins: [
                .plugin(name: "BuildMetalShaders")
            ]
        ),
        .executableTarget(
            name: "MetalShaderCompiler"
        ),
        .plugin(
            name: "BuildMetalShaders",
            capability: .buildTool(),
            dependencies: ["MetalShaderCompiler"]
        ),
        .testTarget(
            name: "VoxelGameKitTests",
            dependencies: ["VoxelGameKit"]
        ),
    ]
)
