import Testing
import simd

@testable import VoxelGameKit

struct VoxelMesherTests {
    @Test
    func singleVoxelProducesOnlyVisibleFaces() {
        let world = VoxelWorld(gridSize: 4, generation: .empty)
        world.setSolid(true, x: 1, y: 1, z: 1)

        let mesh = VoxelMesher().makeWorldMesh(for: world)

        #expect(mesh.vertices.count == 36)
    }

    @Test
    func neighboringVoxelsCullSharedFace() {
        let world = VoxelWorld(gridSize: 4, generation: .empty)
        world.setSolid(true, x: 1, y: 1, z: 1)
        world.setSolid(true, x: 2, y: 1, z: 1)

        let mesh = VoxelMesher().makeWorldMesh(for: world)

        #expect(mesh.vertices.count == 60)
    }

    @Test
    func topFacesUseGrassColorAtHighElevation() {
        let world = VoxelWorld(gridSize: 32, generation: .empty)
        world.setSolid(true, x: 3, y: 20, z: 3)

        let mesh = VoxelMesher().makeWorldMesh(for: world)

        let topFaceColor = mesh.vertices.first { $0.normal == SIMD3<Float>(0, 1, 0) }?.color
        #expect(topFaceColor == SIMD3<Float>(0.2, 0.8, 0.2))
    }
}
