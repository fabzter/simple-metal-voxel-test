import Foundation
import VoxelGameKit
import simd

struct DebugHUDSnapshot {
    let cameraPosition: SIMD3<Float>
    let yawDegrees: Float
    let pitchDegrees: Float
    let meshRevision: UInt64
    let vertexCount: Int
    let worldSeed: UInt64?
    let materialDebugMode: String
    let targetCellDescription: String

    init(scene: GameScene, renderer: Renderer) {
        cameraPosition = scene.camera.position
        yawDegrees = scene.player.cameraYaw * 180.0 / .pi
        pitchDegrees = scene.player.cameraPitch * 180.0 / .pi
        meshRevision = scene.world.meshRevision
        vertexCount = renderer.currentVertexCount
        materialDebugMode = renderer.materialDebugMode.displayName

        if let target = scene.currentTarget?.solidCell {
            targetCellDescription = "(\(target.x), \(target.y), \(target.z))"
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
