import simd

struct ChunkBounds {
    static func bounds(for chunkIndex: VoxelChunkIndex, chunkSize: Int) -> AxisAlignedBoundingBox {
        let min = SIMD3<Float>(
            Float(chunkIndex.x * chunkSize) - 0.5,
            Float(chunkIndex.y * chunkSize) - 0.5,
            Float(chunkIndex.z * chunkSize) - 0.5)
        let max = SIMD3<Float>(
            Float((chunkIndex.x + 1) * chunkSize) - 0.5,
            Float((chunkIndex.y + 1) * chunkSize) - 0.5,
            Float((chunkIndex.z + 1) * chunkSize) - 0.5)
        return AxisAlignedBoundingBox(minimum: min, maximum: max)
    }
}
