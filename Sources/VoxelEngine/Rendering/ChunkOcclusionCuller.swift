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

        // A chunk the camera is inside or directly beside must never be occlusion-culled. At
        // close range the solid surface the player faces lives in the chunk interior, not at a
        // sampled AABB corner, so every corner ray can read as occluded and wrongly hide the
        // chunk — the block in front of the player turns see-through. Exempt the chunk's
        // 3x3x3 neighborhood by growing its AABB one chunk per axis and testing containment.
        let margin = Float(world.chunkSize)
        let p = camera.position
        if p.x >= bounds.minimum.x - margin, p.x <= bounds.maximum.x + margin,
           p.y >= bounds.minimum.y - margin, p.y <= bounds.maximum.y + margin,
           p.z >= bounds.minimum.z - margin, p.z <= bounds.maximum.z + margin {
            return true
        }

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
