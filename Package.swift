// swift-tools-version: 6.1

import PackageDescription

// Package layout:
// - VoxelGame: thin AppKit executable target.
// - VoxelGameKit: reusable gameplay/rendering library.
// - MetalShaderCompiler + BuildMetalShaders: build-time `.metal` -> `.metallib` pipeline.
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
            exclude: ["Shaders"],
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
