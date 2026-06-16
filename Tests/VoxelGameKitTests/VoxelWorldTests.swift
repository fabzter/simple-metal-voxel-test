import Testing

@testable import VoxelGameKit

struct VoxelWorldTests {
    @Test
    func outsideBoundsRulesStayStable() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)

        #expect(world.isSolid(x: 0, y: -1, z: 0))
        #expect(!world.isSolid(x: -1, y: 0, z: 0))
        #expect(!world.isSolid(x: 8, y: 0, z: 0))
        #expect(!world.isSolid(x: 0, y: 8, z: 0))
        #expect(!world.isSolid(x: 0, y: 0, z: 8))
    }

    @Test
    func singleVoxelProducesOnlyVisibleFaces() {
        let world = VoxelWorld(gridSize: 4, generation: .empty)
        world.setSolid(true, x: 1, y: 1, z: 1)

        let mesh = world.buildMesh()

        #expect(mesh.count == 36)
    }

    @Test
    func neighboringVoxelsCullSharedFace() {
        let world = VoxelWorld(gridSize: 4, generation: .empty)
        world.setSolid(true, x: 1, y: 1, z: 1)
        world.setSolid(true, x: 2, y: 1, z: 1)

        let mesh = world.buildMesh()

        #expect(mesh.count == 60)
    }
}
