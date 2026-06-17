import simd

// A tiny voxel ray marcher used for block editing.
//
// We step forward from the camera in small increments, convert each sample point into the voxel
// cell that contains it, and stop when we hit a solid block.
struct VoxelRaycaster {
    let maxDistance: Float
    let stepSize: Float

    init(maxDistance: Float = 8.0, stepSize: Float = 0.05) {
        self.maxDistance = maxDistance
        self.stepSize = stepSize
    }

    func raycast(camera: CameraState, in world: VoxelWorld) -> VoxelRaycastHit? {
        var previousEmptyCell: VoxelIndex?
        var lastVisitedCell: VoxelIndex?

        var distance: Float = 0.0
        while distance <= maxDistance {
            let samplePoint = camera.position + camera.forward * distance
            let currentCell = VoxelIndex(point: samplePoint)

            if currentCell != lastVisitedCell {
                if world.isSolid(x: currentCell.x, y: currentCell.y, z: currentCell.z) {
                    return VoxelRaycastHit(
                        solidCell: currentCell,
                        placementCell: previousEmptyCell)
                }

                previousEmptyCell = currentCell
                lastVisitedCell = currentCell
            }

            distance += stepSize
        }

        return nil
    }
}

struct VoxelRaycastHit {
    let solidCell: VoxelIndex
    let placementCell: VoxelIndex?
}

struct VoxelIndex: Equatable {
    let x: Int
    let y: Int
    let z: Int

    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(point: SIMD3<Float>) {
        self.init(
            x: Int(floor(point.x + 0.5)),
            y: Int(floor(point.y + 0.5)),
            z: Int(floor(point.z + 0.5)))
    }
}
