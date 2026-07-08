import simd

// A conservative voxel-world occlusion test used after frustum culling.
//
// We cast a few rays from the camera toward representative points of the chunk bounds. If all of
// those rays hit some other chunk first, we treat the chunk as occluded. If any sample point is
// directly visible (or the first hit belongs to the tested chunk), we keep it.
struct ChunkOcclusionCuller {
    private let raycaster = VoxelRaycaster()

    func isVisible(chunkIndex: VoxelChunkIndex, world: VoxelWorld, camera: CameraState) -> Bool {
        let bounds = ChunkBounds.bounds(for: chunkIndex, chunkSize: world.chunkSize)
        let samplePoints = samplePoints(for: bounds)

        for samplePoint in samplePoints {
            let toSample = samplePoint - camera.position
            let distance = simd_length(toSample)
            guard distance > 0.001 else {
                return true
            }

            let direction = toSample / distance
            let hit = raycaster.raycast(
                origin: camera.position,
                direction: direction,
                startDistance: 0.05,
                maxDistance: distance + 0.25,
                in: world)

            guard let hit else {
                return true
            }

            if let hitChunk = world.chunkIndex(containing: hit.solidCell), hitChunk == chunkIndex {
                return true
            }

            if hit.distance >= distance - 0.15 {
                return true
            }
        }

        return false
    }

    private func samplePoints(for bounds: AxisAlignedBoundingBox) -> [SIMD3<Float>] {
        let center = (bounds.minimum + bounds.maximum) * 0.5
        return [
            center,
            SIMD3(bounds.minimum.x, bounds.minimum.y, bounds.minimum.z),
            SIMD3(bounds.maximum.x, bounds.minimum.y, bounds.minimum.z),
            SIMD3(bounds.minimum.x, bounds.maximum.y, bounds.minimum.z),
            SIMD3(bounds.maximum.x, bounds.maximum.y, bounds.minimum.z),
            SIMD3(bounds.minimum.x, bounds.minimum.y, bounds.maximum.z),
            SIMD3(bounds.maximum.x, bounds.minimum.y, bounds.maximum.z),
            SIMD3(bounds.minimum.x, bounds.maximum.y, bounds.maximum.z),
            SIMD3(bounds.maximum.x, bounds.maximum.y, bounds.maximum.z),
        ]
    }
}
