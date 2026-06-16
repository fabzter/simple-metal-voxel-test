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
    func sameSeedProducesSameTerrain() {
        let config = VoxelWorldConfiguration(seed: 1234)
        let worldA = VoxelWorld(gridSize: 16, generation: .terrain(config))
        let worldB = VoxelWorld(gridSize: 16, generation: .terrain(config))

        #expect(worldA.solidGrid == worldB.solidGrid)
    }

    @Test
    func differentSeedsProduceDifferentTerrain() {
        let worldA = VoxelWorld(gridSize: 16, generation: .terrain(.init(seed: 1)))
        let worldB = VoxelWorld(gridSize: 16, generation: .terrain(.init(seed: 2)))

        #expect(worldA.solidGrid != worldB.solidGrid)
    }
}
