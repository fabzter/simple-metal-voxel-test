import Testing
import simd

@testable import VoxelEngine

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

    @Test
    func stitchedCoarseBoundaryAddsFineResolutionEdgeVertices() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<4 { for z in 0..<4 { world.setSolid(true, x: x, y: 0, z: z) } }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let coarseMesh = world.makeWorldMesh(for: chunk, voxelStride: 2)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(positiveZFinerStride: 1))
        #expect(stitchedMesh.vertices.count > coarseMesh.vertices.count)
    }

    @Test
    func partialSeamExposureAlwaysEmitsBoundarySubquads() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<2 {
            for y in 0..<2 { for z in 2..<4 { world.setSolid(true, x: x, y: y, z: z) } }
        }
        world.setSolid(true, x: 0, y: 0, z: 4)
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(positiveZFinerStride: 1))
        let boundaryFaceVertices = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 0, 1) && abs($0.position.z - 3.5) < 0.001
        }
        #expect(boundaryFaceVertices.count == 24)
    }

    @Test
    func seamBoundaryFacesAreEmittedDoubleSided() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<2 {
            for y in 0..<2 { for z in 2..<4 { world.setSolid(true, x: x, y: y, z: z) } }
        }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(positiveZFinerStride: 1))
        let fwd = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 0, 1) && abs($0.position.z - 3.5) < 0.001
        }
        let rev = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 0, -1) && abs($0.position.z - 3.5) < 0.001
        }
        #expect(!fwd.isEmpty && fwd.count == rev.count)
    }

    @Test
    func coarseTopFaceUsesActualOccupiedHeight() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<2 { for z in 0..<2 { world.setSolid(true, x: x, y: 0, z: z) } }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let mesh = world.makeWorldMesh(for: chunk, voxelStride: 2)
        let top = mesh.vertices.filter { $0.normal == SIMD3<Float>(0, 1, 0) }
        #expect(!top.isEmpty && top.allSatisfy { abs($0.position.y - 0.5) < 0.001 })
    }

    @Test
    func mixedSeamTopFacesSlightlyOverlapBoundaryEdge() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 2..<4 { for z in 2..<4 { world.setSolid(true, x: x, y: 0, z: z) } }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(
                positiveXFinerStride: 1, positiveZFinerStride: 1))
        let topVertices = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 1, 0) && abs($0.position.y - 0.5) < 0.001
        }
        #expect(topVertices.map(\.position.x).max()! > 3.5)
        #expect(topVertices.map(\.position.z).max()! > 3.5)
    }

    @Test
    func adjacentSeamEdgesCreateInteriorCornerVertex() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 2..<4 { for z in 2..<4 { world.setSolid(true, x: x, y: 0, z: z) } }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(
                positiveXFinerStride: 1, positiveZFinerStride: 1))
        let topFaceVertices = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 1, 0) && abs($0.position.y - 0.5) < 0.001
        }
        let hasInteriorCorner = topFaceVertices.contains {
            abs($0.position.x - 2.5) < 0.03 && abs($0.position.z - 2.5) < 0.03
        }
        #expect(hasInteriorCorner)
        #expect(topFaceVertices.count == 24)
    }

    @Test
    func stitchedSideSeamAddsTopSkirtToCoarseCeiling() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<2 {
            world.setSolid(true, x: x, y: 0, z: 2)
            world.setSolid(true, x: x, y: 0, z: 3)
        }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(positiveZFinerStride: 1))
        let vertices = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 0, 1) && abs($0.position.z - 3.5) < 0.001
        }
        #expect(abs(vertices.map(\.position.y).min()! + 0.5) < 0.001)
        #expect(abs(vertices.map(\.position.y).max()! - 1.5) < 0.001)
    }

    @Test
    func topSkirtStillEmitsWhenNeighborRowIsSolid() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<2 { for z in 2..<5 { world.setSolid(true, x: x, y: 0, z: z) } }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(positiveZFinerStride: 1))
        let vertices = stitchedMesh.vertices.filter {
            $0.normal == SIMD3<Float>(0, 0, 1) && abs($0.position.z - 3.5) < 0.001
        }
        #expect(!vertices.isEmpty)
        #expect(vertices.map(\.position.y).max() == 1.5)
    }

    @Test
    func seamBoundaryFacesSlightlyOverlapNominalEdges() {
        let world = VoxelWorld(gridSize: 8, chunkSize: 4, generation: .empty)
        for x in 0..<2 {
            for y in 0..<2 { for z in 2..<4 { world.setSolid(true, x: x, y: y, z: z) } }
        }
        let chunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let stitchedMesh = world.makeWorldMesh(
            for: chunk, voxelStride: 2,
            seamConfiguration: ChunkSeamConfiguration(positiveZFinerStride: 1))
        let boundaryVertices = stitchedMesh.vertices.filter {
            abs($0.position.z - 3.5) < 0.001 && abs($0.normal.z) > 0.9
        }
        let xs = boundaryVertices.map(\.position.x)
        #expect(xs.contains { $0 > 0.45 && $0 < 0.5 })
        #expect(xs.contains { $0 > 0.5 && $0 < 0.55 })
    }

    @Test
    func lod2ChunkMeshCoversRaymarchSolidHit() {
        let world = VoxelWorld(
            gridSize: 256, chunkSize: 16, generation: .terrain(VoxelWorldConfiguration()))
        let chunk = VoxelChunkIndex(x: 9, y: 1, z: 0)
        #expect(world.isSolid(x: 155, y: 19, z: 4))
        let mesh = world.makeWorldMesh(for: chunk, voxelStride: 4)
        let at1555 = mesh.vertices.filter {
            $0.normal.x > 0.9 && abs($0.position.x - 155.5) < 0.01
        }
        #expect(!at1555.isEmpty, "LOD2 mesh for [9,1,0] missing positive-X face at x=155.5")
    }
}
