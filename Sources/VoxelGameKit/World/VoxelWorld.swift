public final class VoxelWorld {
    public enum Generation: Sendable {
        case proceduralTerrain
        case empty
    }

    public let gridSize: Int
    public private(set) var solidGrid: [Bool]

    private let terrainGenerator = VoxelTerrainGenerator()
    private let mesher = VoxelMesher()

    public init(gridSize: Int = 64, generation: Generation = .proceduralTerrain) {
        self.gridSize = gridSize
        self.solidGrid = Array(repeating: false, count: gridSize * gridSize * gridSize)

        if generation == .proceduralTerrain {
            terrainGenerator.populate(self)
        }
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

    public func setSolid(_ isSolid: Bool, x: Int, y: Int, z: Int) {
        guard x >= 0, x < gridSize, y >= 0, y < gridSize, z >= 0, z < gridSize else {
            return
        }

        solidGrid[index(x: x, y: y, z: z)] = isSolid
    }

    func buildMesh() -> [Vertex] {
        makeWorldMesh().vertices
    }

    func makeWorldMesh() -> WorldMesh {
        mesher.makeWorldMesh(for: self)
    }

    private func index(x: Int, y: Int, z: Int) -> Int {
        x + y * gridSize + z * gridSize * gridSize
    }
}
