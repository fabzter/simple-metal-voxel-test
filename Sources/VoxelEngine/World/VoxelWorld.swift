public final class VoxelWorld {
    public enum Generation: Sendable, Equatable {
        case terrain(VoxelWorldConfiguration)
        case empty
    }

    public let gridSize: Int
    public let chunkSize: Int
    public private(set) var generation: Generation
    public private(set) var solidGrid: BitGrid
    public private(set) var meshRevision: UInt64 = 0

    private let mesher = VoxelMesher()
    private var chunkRevisions: [VoxelChunkIndex: UInt64]
    private let chunkIndices: [VoxelChunkIndex]
    private var explicitMaterials: [Int: BlockMaterialType] = [:]
    /// Solid-voxel count per chunk. The renderer uses this to skip all-air chunks
    /// before doing any LOD, frustum, occlusion, or meshing work.
    private var chunkSolidCounts: [VoxelChunkIndex: Int] = [:]

    public init(
        gridSize: Int = 64,
        chunkSize: Int = 16,
        generation: Generation = .terrain(.default)
    ) {
        self.gridSize = gridSize
        self.chunkSize = chunkSize
        self.generation = generation
        self.solidGrid = BitGrid(count: gridSize * gridSize * gridSize)
        self.chunkIndices = Self.makeChunkIndices(gridSize: gridSize, chunkSize: chunkSize)
        self.chunkRevisions = Dictionary(uniqueKeysWithValues: chunkIndices.map { ($0, 0) })

        switch generation {
        case .terrain(let configuration):
            VoxelTerrainGenerator(configuration: configuration).populate(self)
        case .empty:
            break
        }

        meshRevision = 0
        resetChunkRevisions()
    }

    public func isSolid(x: Int, y: Int, z: Int) -> Bool {
        if y < 0 {
            return true
        }

        if x < 0 || x >= gridSize || y >= gridSize || z < 0 || z >= gridSize {
            return false
        }

        return solidGrid[index(x: x, y: y, z: z)]
    }

    /// Returns the current solid grid words and explicit materials for serialization.
    public func makeSaveSnapshot() -> (words: [UInt64], materials: [Int: BlockMaterialType]) {
        (solidGrid.words, explicitMaterials)
    }

    /// Restores a world from saved grid data.  Returns `nil` when the word count or
    /// trailing bits are invalid.  The world starts empty and the grid is injected
    /// directly, so chunks are revision-zero and the renderer seeds its revision map
    /// from them.
    ///
    /// `generation` is set to `.terrain(seed)` afterwards as *provenance*: it records
    /// which seed originally built this terrain so the HUD/inspector, re-save, and
    /// Reset World keep the right seed.  The restored grid — not the generator —
    /// defines the current content.
    public static func restored(
        gridSize: Int,
        chunkSize: Int,
        seed: UInt64,
        words: [UInt64],
        materials: [Int: BlockMaterialType]
    ) -> VoxelWorld? {
        guard let restoredGrid = BitGrid(count: gridSize * gridSize * gridSize, words: words) else {
            return nil
        }
        let world = VoxelWorld(gridSize: gridSize, chunkSize: chunkSize, generation: .empty)
        world.solidGrid = restoredGrid
        world.explicitMaterials = materials
        // Restores inject the bit grid directly instead of replaying `setSolid`, so rebuild
        // the per-chunk occupancy table once here.
        world.recomputeChunkSolidCounts()
        world.generation = .terrain(VoxelWorldConfiguration(seed: seed))
        return world
    }

    public func setSolid(_ isSolid: Bool, x: Int, y: Int, z: Int) {
        setSolid(isSolid, x: x, y: y, z: z, material: nil)
    }

    public func setSolid(_ isSolid: Bool, x: Int, y: Int, z: Int, material: BlockMaterialType?) {
        guard x >= 0, x < gridSize, y >= 0, y < gridSize, z >= 0, z < gridSize else {
            return
        }

        let cellIndex = index(x: x, y: y, z: z)
        let existingValue = solidGrid[cellIndex]
        let existingMaterial = explicitMaterials[cellIndex]

        if existingValue == isSolid {
            if isSolid, let material, existingMaterial != material {
                explicitMaterials[cellIndex] = material
                invalidateMeshAround(x: x, y: y, z: z)
            }
            return
        }

        solidGrid[cellIndex] = isSolid
        let chunk = VoxelChunkIndex(x: x / chunkSize, y: y / chunkSize, z: z / chunkSize)
        chunkSolidCounts[chunk, default: 0] += isSolid ? 1 : -1
        if isSolid {
            if let material {
                explicitMaterials[cellIndex] = material
            } else {
                explicitMaterials.removeValue(forKey: cellIndex)
            }
        } else {
            explicitMaterials.removeValue(forKey: cellIndex)
        }
        invalidateMeshAround(x: x, y: y, z: z)
    }

    public func materialType(x: Int, y: Int, z: Int) -> BlockMaterialType? {
        guard isSolid(x: x, y: y, z: z) else {
            return nil
        }

        let cellIndex = index(x: x, y: y, z: z)
        if let explicitMaterial = explicitMaterials[cellIndex] {
            return explicitMaterial
        }

        if y >= 22 { return .snow }
        if y >= 14 { return .grass }
        if y >= 10 { return .moss }
        return .stone
    }

    public func allChunkIndices() -> [VoxelChunkIndex] {
        chunkIndices
    }

    public func chunkRevision(for chunkIndex: VoxelChunkIndex) -> UInt64 {
        chunkRevisions[chunkIndex, default: 0]
    }

    /// Returns whether a chunk contains any solid voxels. O(1).
    public func chunkHasSolidVoxels(_ chunkIndex: VoxelChunkIndex) -> Bool {
        chunkSolidCounts[chunkIndex, default: 0] > 0
    }

    func chunkIndex(containing cell: VoxelIndex) -> VoxelChunkIndex? {
        guard cell.x >= 0, cell.x < gridSize, cell.y >= 0, cell.y < gridSize, cell.z >= 0,
            cell.z < gridSize
        else {
            return nil
        }

        return VoxelChunkIndex(
            x: cell.x / chunkSize,
            y: cell.y / chunkSize,
            z: cell.z / chunkSize)
    }

    func buildMesh() -> [Vertex] {
        chunkIndices.flatMap {
            makeWorldMesh(for: $0, voxelStride: 1, seamConfiguration: .none).vertices
        }
    }

    func makeWorldMesh(for chunkIndex: VoxelChunkIndex, voxelStride: Int) -> WorldMesh {
        makeWorldMesh(for: chunkIndex, voxelStride: voxelStride, seamConfiguration: .none)
    }

    func makeWorldMesh(
        for chunkIndex: VoxelChunkIndex,
        voxelStride: Int,
        seamConfiguration: ChunkSeamConfiguration
    ) -> WorldMesh {
        mesher.makeWorldMesh(
            for: self,
            chunkIndex: chunkIndex,
            voxelStride: voxelStride,
            seamConfiguration: seamConfiguration)
    }

    public func topSolidY(inColumnX x: Int, z: Int, withinYRange yRange: ClosedRange<Int>) -> Int? {
        let upper = min(yRange.upperBound, gridSize - 1)
        let lower = max(yRange.lowerBound, 0)
        guard lower <= upper else { return nil }

        for y in stride(from: upper, through: lower, by: -1) {
            if isSolid(x: x, y: y, z: z) {
                return y
            }
        }
        return nil
    }

    private func index(x: Int, y: Int, z: Int) -> Int {
        x + y * gridSize + z * gridSize * gridSize
    }

    private func invalidateMeshAround(x: Int, y: Int, z: Int) {
        meshRevision &+= 1
        for chunkIndex in affectedChunkIndices(forVoxelX: x, y: y, z: z) {
            chunkRevisions[chunkIndex, default: 0] &+= 1
        }
    }

    private func affectedChunkIndices(forVoxelX x: Int, y: Int, z: Int) -> Set<VoxelChunkIndex> {
        var xChunks = [x / chunkSize]
        var yChunks = [y / chunkSize]
        var zChunks = [z / chunkSize]

        if x % chunkSize == 0, x > 0 {
            xChunks.append((x - 1) / chunkSize)
        }
        if x % chunkSize == chunkSize - 1, x + 1 < gridSize {
            xChunks.append((x + 1) / chunkSize)
        }
        if y % chunkSize == 0, y > 0 {
            yChunks.append((y - 1) / chunkSize)
        }
        if y % chunkSize == chunkSize - 1, y + 1 < gridSize {
            yChunks.append((y + 1) / chunkSize)
        }
        if z % chunkSize == 0, z > 0 {
            zChunks.append((z - 1) / chunkSize)
        }
        if z % chunkSize == chunkSize - 1, z + 1 < gridSize {
            zChunks.append((z + 1) / chunkSize)
        }

        var indices: Set<VoxelChunkIndex> = []
        for chunkX in xChunks {
            for chunkY in yChunks {
                for chunkZ in zChunks {
                    indices.insert(VoxelChunkIndex(x: chunkX, y: chunkY, z: chunkZ))
                }
            }
        }
        return indices
    }

    private func recomputeChunkSolidCounts() {
        chunkSolidCounts.removeAll(keepingCapacity: true)

        for z in 0..<gridSize {
            for y in 0..<gridSize {
                for x in 0..<gridSize where solidGrid[index(x: x, y: y, z: z)] {
                    let chunk = VoxelChunkIndex(
                        x: x / chunkSize,
                        y: y / chunkSize,
                        z: z / chunkSize)
                    chunkSolidCounts[chunk, default: 0] += 1
                }
            }
        }
    }

    private func resetChunkRevisions() {
        for chunkIndex in chunkIndices {
            chunkRevisions[chunkIndex] = 0
        }
    }

    private static func makeChunkIndices(gridSize: Int, chunkSize: Int) -> [VoxelChunkIndex] {
        let chunkCount = max(1, (gridSize + chunkSize - 1) / chunkSize)
        var indices: [VoxelChunkIndex] = []

        for z in 0..<chunkCount {
            for y in 0..<chunkCount {
                for x in 0..<chunkCount {
                    indices.append(VoxelChunkIndex(x: x, y: y, z: z))
                }
            }
        }

        return indices
    }
}
