import Testing
import simd

@testable import VoxelGameKit

struct VoxelRaycasterTests {
    @Test
    func skipsStartingSolidCellAndHitsVisibleBlockAhead() {
        let world = VoxelWorld(gridSize: 16, generation: .empty)
        world.setSolid(true, x: 8, y: 2, z: 8)
        world.setSolid(true, x: 8, y: 2, z: 5)

        let camera = CameraState(
            position: SIMD3<Float>(8, 1.6, 8),
            yaw: 0,
            pitch: 0)

        let hit = VoxelRaycaster().raycast(camera: camera, in: world)

        #expect(hit?.solidCell == VoxelIndex(x: 8, y: 2, z: 5))
        #expect(hit?.placementCell == VoxelIndex(x: 8, y: 2, z: 6))
    }
}
