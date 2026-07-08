// swift-tools-version: 6.1

import PackageDescription

// Package layout — the engine is the product, the demo is the showcase:
// - VoxelEngine: the reusable voxel engine library (world, meshing, rendering,
//   player physics, persistence). This is the main product of the repository.
//   It never depends on the demo.
// - VoxelDemo: a small AppKit game built ON TOP of VoxelEngine to demonstrate
//   it end to end (windowing, input mapping, HUD/UI, sounds, save UX).
// - MetalShaderCompiler + BuildMetalShaders: build-time `.metal` -> `.metallib`
//   pipeline used by the engine target.
let package = Package(
    name: "VoxelEngine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The engine library is the primary product of this repo.
        .library(
            name: "VoxelEngine",
            targets: ["VoxelEngine"]
        ),
        // The demo game executable showcases the engine.
        .executable(
            name: "VoxelDemo",
            targets: ["VoxelDemo"]
        ),
    ],
    targets: [
        // MARK: Engine (main product)
        .target(
            name: "VoxelEngine",
            exclude: ["Shaders"],
            plugins: [
                .plugin(name: "BuildMetalShaders")
            ]
        ),

        // MARK: Demo game (depends on the engine, never the reverse)
        .executableTarget(
            name: "VoxelDemo",
            dependencies: ["VoxelEngine"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        ),

        // MARK: Build tooling
        .executableTarget(
            name: "MetalShaderCompiler"
        ),
        .plugin(
            name: "BuildMetalShaders",
            capability: .buildTool(),
            dependencies: ["MetalShaderCompiler"]
        ),

        // MARK: Tests
        .testTarget(
            name: "VoxelEngineTests",
            dependencies: ["VoxelEngine"]
        ),
        .testTarget(
            name: "VoxelDemoTests",
            dependencies: ["VoxelDemo"]
        ),
    ]
)
