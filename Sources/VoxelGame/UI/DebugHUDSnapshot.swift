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
    let lodDistribution: String
    let worldSeed: UInt64?
    let materialDebugMode: String
    let lodTintOverlayMode: String
    let selectedPlacementMaterial: String
    let targetMaterial: String?
    let targetFace: String?
    let targetDistanceMeters: Float?
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
        lodDistribution = renderer.currentLODCounts.keys.sorted().map {
            "L\($0):\(renderer.currentLODCounts[$0] ?? 0)"
        }.joined(separator: " ")
        materialDebugMode = renderer.materialDebugMode.displayName
        lodTintOverlayMode = renderer.debugSettings.lodTintOverlayMode.displayName
        selectedPlacementMaterial = scene.selectedPlacementMaterial.displayName
        frameTimeMilliseconds = frameTimeSeconds * 1000.0
        framesPerSecond = frameTimeSeconds > 0.0001 ? 1.0 / frameTimeSeconds : 0

        if let hit = scene.currentTarget, let target = scene.currentTarget?.solidCell {
            let face = hit.face?.label ?? "unknown"
            targetCellDescription = "(\(target.x), \(target.y), \(target.z)) [\(face)]"
            targetMaterial =
                scene.world.materialType(x: target.x, y: target.y, z: target.z)?.displayName
            targetFace = hit.face?.label
            targetDistanceMeters = hit.distance
        } else {
            targetCellDescription = "none"
            targetMaterial = nil
            targetFace = nil
            targetDistanceMeters = nil
        }

        switch scene.world.generation {
        case .terrain(let configuration):
            worldSeed = configuration.seed
        case .empty:
            worldSeed = nil
        }
    }
}
