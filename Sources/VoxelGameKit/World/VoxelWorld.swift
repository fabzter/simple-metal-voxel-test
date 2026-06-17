public final class VoxelWorld {
    public enum Generation: Sendable, Equatable {
        case terrain(VoxelWorldConfiguration)
        case empty
    }

    public let gridSize: Int
    public let chunkSize: Int
    public let generation: Generation
    public private(set) var solidGrid: [Bool]
    public private(set) var meshRevision: UInt64 = 0

    private let mesher = VoxelMesher()
    private var chunkRevisions: [VoxelChunkIndex: UInt64]
    private let chunkIndices: [VoxelChunkIndex]

    public init(
        gridSize: Int = 64,
        chunkSize: Int = 16,
        generation: Generation = .terrain(.default)
    ) {
        self.gridSize = gridSize
        self.chunkSize = chunkSize
        self.generation = generation
        self.solidGrid = Array(repeating: false, count: gridSize * gridSize * gridSize)
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

    // The world is stored as a dense 3D boolean grid.
    // `true` means a voxel cube exists at that integer cell.
    public func isSolid(x: Int, y: Int, z: Int) -> Bool {
        if y < 0 {
            return true
        }

        if x < 0 || x >= gridSize || y >= gridSize || z < 0 || z >= gridSize {
            return false
        }

        return solidGrid[index(x: x, y: y, z: z)]
    }

    // Any real change to the voxel grid increments `meshRevision`.
    // The renderer watches both the world-wide revision and the per-chunk revisions so it can
    // rebuild only the chunk meshes affected by an edit.
    public func setSolid(_ isSolid: Bool, x: Int, y: Int, z: Int) {
        guard x >= 0, x < gridSize, y >= 0, y < gridSize, z >= 0, z < gridSize else {
            return
        }

        let cellIndex = index(x: x, y: y, z: z)
        guard solidGrid[cellIndex] != isSolid else {
            return
        }

        solidGrid[cellIndex] = isSolid
        meshRevision &+= 1

        for chunkIndex in affectedChunkIndices(forVoxelX: x, y: y, z: z) {
            chunkRevisions[chunkIndex, default: 0] &+= 1
        }
    }

    public func allChunkIndices() -> [VoxelChunkIndex] {
        chunkIndices
    }

    public func chunkRevision(for chunkIndex: VoxelChunkIndex) -> UInt64 {
        chunkRevisions[chunkIndex, default: 0]
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

    // Convenience used by tests and older call sites.
    func buildMesh() -> [Vertex] {
        chunkIndices.flatMap { makeWorldMesh(for: $0).vertices }
    }

    func makeWorldMesh(for chunkIndex: VoxelChunkIndex) -> WorldMesh {
        mesher.makeWorldMesh(for: self, chunkIndex: chunkIndex)
    }

    private func index(x: Int, y: Int, z: Int) -> Int {
        x + y * gridSize + z * gridSize * gridSize
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
