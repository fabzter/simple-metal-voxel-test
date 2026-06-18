import Testing
import simd

@testable import VoxelGameKit

struct GameSceneEditingTests {
    @Test
    func defaultSceneSpawnsPlayerAboveTerrainSurface() {
        let scene = GameScene(gridSize: 64, worldGeneration: .terrain(.default))
        let playerCellX = Int(floor(scene.player.position.x))
        let playerCellZ = Int(floor(scene.player.position.z))
        let surfaceY = scene.world.topSolidY(
            inColumnX: playerCellX,
            z: playerCellZ,
            withinYRange: 0...(scene.world.gridSize - 1))

        #expect(surfaceY != nil)
        #expect(scene.player.position.y >= Float((surfaceY ?? 0) + 1))
        #expect(scene.player.isGrounded)
    }

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
