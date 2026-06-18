public struct LODLevelConfiguration: Sendable, Equatable {
    // Maximum chunk-ring distance from the camera at which this level is used.
    public var maxChunkDistance: Int

    // Sample stride in voxel space. 1 = full detail, 2 = merge 2x2x2 cells, etc.
    public var voxelStride: Int

    public init(maxChunkDistance: Int, voxelStride: Int) {
        self.maxChunkDistance = maxChunkDistance
        self.voxelStride = voxelStride
    }
}

public struct LODConfiguration: Sendable, Equatable {
    public var levels: [LODLevelConfiguration]

    public init(levels: [LODLevelConfiguration]) {
        self.levels = levels.sorted { $0.maxChunkDistance < $1.maxChunkDistance }
    }

    public static let `default` = LODConfiguration(levels: [
        .init(maxChunkDistance: 2, voxelStride: 1),
        .init(maxChunkDistance: 5, voxelStride: 2),
        .init(maxChunkDistance: 9, voxelStride: 4),
    ])
}
