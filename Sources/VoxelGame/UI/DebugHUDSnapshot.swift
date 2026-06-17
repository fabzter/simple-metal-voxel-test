import Foundation
import VoxelGameKit
import simd

struct DebugHUDSnapshot {
    let cameraPosition: SIMD3<Float>
    let yawDegrees: Float
    let pitchDegrees: Float
    let meshRevision: UInt64
    let vertexCount: Int
    let visibleChunkCount: Int
    let worldSeed: UInt64?
    let materialDebugMode: String
    let targetCellDescription: String
    let frameTimeMilliseconds: Float
    let framesPerSecond: Float

    init(scene: GameScene, renderer: Renderer, frameTimeSeconds: Float) {
        cameraPosition = scene.camera.position
        yawDegrees = scene.player.cameraYaw * 180.0 / .pi
        pitchDegrees = scene.player.cameraPitch * 180.0 / .pi
        meshRevision = scene.world.meshRevision
        vertexCount = renderer.currentVertexCount
        visibleChunkCount = renderer.currentVisibleChunkCount
        materialDebugMode = renderer.materialDebugMode.displayName
        frameTimeMilliseconds = frameTimeSeconds * 1000.0
        framesPerSecond = frameTimeSeconds > 0.0001 ? 1.0 / frameTimeSeconds : 0

        if let target = scene.currentTarget?.solidCell {
            let face = scene.currentTarget?.face?.label ?? "unknown"
            targetCellDescription = "(\(target.x), \(target.y), \(target.z)) [\(face)]"
        } else {
            targetCellDescription = "none"
        }

        switch scene.world.generation {
        case .terrain(let configuration):
            worldSeed = configuration.seed
        case .empty:
            worldSeed = nil
        }
    }
}
