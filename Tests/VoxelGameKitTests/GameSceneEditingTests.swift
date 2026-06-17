import Testing
import simd

@testable import VoxelGameKit

struct GameSceneEditingTests {
    @Test
    func removeActionDeletesTargetedVoxel() {
        let player = PlayerController(
            position: SIMD3<Float>(8, 0, 8),
            cameraYaw: 0,
            cameraPitch: 0)
        let scene = GameScene(gridSize: 16, worldGeneration: .empty, player: player)
        scene.world.setSolid(true, x: 8, y: 2, z: 5)

        scene.update(
            dt: 0,
            input: PlayerInput(),
            lookDelta: .zero,
            editActions: [.remove])

        #expect(!scene.world.isSolid(x: 8, y: 2, z: 5))
    }

    @Test
    func placeActionFillsCellBeforeHitBlock() {
        let player = PlayerController(
            position: SIMD3<Float>(8, 0, 8),
            cameraYaw: 0,
            cameraPitch: 0)
        let scene = GameScene(gridSize: 16, worldGeneration: .empty, player: player)
        scene.world.setSolid(true, x: 8, y: 2, z: 5)

        scene.update(
            dt: 0,
            input: PlayerInput(),
            lookDelta: .zero,
            editActions: [.place])

        #expect(scene.world.isSolid(x: 8, y: 2, z: 6))
    }
}
