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
        .init(maxChunkDistance: 4, voxelStride: 1),
        .init(maxChunkDistance: 8, voxelStride: 2),
        .init(maxChunkDistance: 13, voxelStride: 4),
        // A final coarse ring keeps the horizon filled in instead of letting distant terrain
        // disappear abruptly once it leaves the third band. Rings are pushed out so stride
        // changes land where a voxel subtends only a few pixels (64/128/208/288 world units).
        .init(maxChunkDistance: 18, voxelStride: 8),
    ])
}
extension LODConfiguration {
    /// Validates that every configured LOD stride is a multiple of every finer stride,
    /// which is required for correct seam stitching. Returns `nil` if valid, or an error
    /// message describing the violation otherwise.
    public func validateStrideChain() -> String? {
        guard levels.count > 1 else {
            return nil
        }

        for i in 1..<levels.count {
            let coarser = levels[i]
            for j in 0..<i {
                let finer = levels[j]
                guard coarser.voxelStride.isMultiple(of: finer.voxelStride) else {
                    return
                        "LOD level \(i) (stride \(coarser.voxelStride)) is not a multiple of LOD level \(j) stride (\(finer.voxelStride)). All coarser LOD strides must be multiples of every finer stride for correct seam stitching."
                }
            }
        }

        return nil
    }
}
