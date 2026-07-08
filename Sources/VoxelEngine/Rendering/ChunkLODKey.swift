struct ChunkLODKey: Hashable {
    let chunkIndex: VoxelChunkIndex
    let lodLevel: Int
    let seamConfiguration: ChunkSeamConfiguration
}
