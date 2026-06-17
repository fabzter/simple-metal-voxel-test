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
    func topFacesUseTexturedModeAtHighElevation() {
        let world = VoxelWorld(gridSize: 32, generation: .empty)
        world.setSolid(true, x: 3, y: 20, z: 3)

        let mesh = VoxelMesher().makeWorldMesh(for: world)

        let topFaceVertex = mesh.vertices.first { $0.normal == SIMD3<Float>(0, 1, 0) }
        #expect(topFaceVertex?.materialMode == MaterialMode.textured.rawValue)
    }

    @Test
    func lowStoneFacesUseFlatColorMode() {
        let world = VoxelWorld(gridSize: 32, generation: .empty)
        world.setSolid(true, x: 3, y: 6, z: 3)

        let mesh = VoxelMesher().makeWorldMesh(for: world)

        let anyFlatVertex = mesh.vertices.contains {
            $0.materialMode == MaterialMode.flatColor.rawValue
        }
        #expect(anyFlatVertex)
    }

    @Test
    func coarserLodProducesLessGeometry() {
        let world = VoxelWorld(gridSize: 32, chunkSize: 16, generation: .empty)

        for x in 0..<8 {
            for y in 0..<8 {
                for z in 0..<8 {
                    world.setSolid(true, x: x, y: y, z: z)
                }
            }
        }

        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let fullMesh = world.makeWorldMesh(for: chunk, voxelStride: 1)
        let coarseMesh = world.makeWorldMesh(for: chunk, voxelStride: 2)

        #expect(coarseMesh.vertices.count < fullMesh.vertices.count)
    }
}
