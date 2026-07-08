import Testing
import simd

@testable import VoxelEngine

struct ChunkOcclusionCullerTests {
    @Test
    func frontChunkCanOccludeRearChunk() {
        let world = VoxelWorld(gridSize: 32, chunkSize: 8, generation: .empty)

        // Fill the whole front chunk with solids so it acts like a wall.
        for x in 0..<8 {
            for y in 0..<8 {
                for z in 8..<16 {
                    world.setSolid(true, x: x, y: y, z: z)
                }
            }
        }

        // Put at least one voxel in the rear chunk so the chunk is non-empty.
        world.setSolid(true, x: 4, y: 4, z: 4)

        let camera = CameraState(position: SIMD3<Float>(4, 4, 24), yaw: 0, pitch: 0)
        let culler = ChunkOcclusionCuller()

        #expect(
            culler.isVisible(
                chunkIndex: VoxelChunkIndex(x: 0, y: 0, z: 1), world: world, camera: camera))
        #expect(
            !culler.isVisible(
                chunkIndex: VoxelChunkIndex(x: 0, y: 0, z: 0), world: world, camera: camera))
    }
}
