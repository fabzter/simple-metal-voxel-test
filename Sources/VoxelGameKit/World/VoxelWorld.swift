public final class VoxelWorld {
    public enum Generation: Sendable, Equatable {
        case terrain(VoxelWorldConfiguration)
        case empty
    }

    public let gridSize: Int
    public private(set) var solidGrid: [Bool]

    private let mesher = VoxelMesher()

    public init(gridSize: Int = 64, generation: Generation = .terrain(.default)) {
        self.gridSize = gridSize
        self.solidGrid = Array(repeating: false, count: gridSize * gridSize * gridSize)

        switch generation {
        case .terrain(let configuration):
            VoxelTerrainGenerator(configuration: configuration).populate(self)
        case .empty:
            break
        }
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

    public func setSolid(_ isSolid: Bool, x: Int, y: Int, z: Int) {
        guard x >= 0, x < gridSize, y >= 0, y < gridSize, z >= 0, z < gridSize else {
            return
        }

        solidGrid[index(x: x, y: y, z: z)] = isSolid
    }

    // Convenience used by tests and older call sites.
    func buildMesh() -> [Vertex] {
        makeWorldMesh().vertices
    }

    // Convert the voxel grid into a renderable triangle mesh by keeping only faces that
    // border empty space.
    func makeWorldMesh() -> WorldMesh {
        mesher.makeWorldMesh(for: self)
    }

    private func index(x: Int, y: Int, z: Int) -> Int {
        x + y * gridSize + z * gridSize * gridSize
    }
}
