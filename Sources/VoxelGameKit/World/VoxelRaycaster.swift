import simd

// A tiny voxel ray marcher used for block editing.
//
// We step forward from the camera in small increments, convert each sample point into the voxel
// cell that contains it, and stop when we hit a solid block.
//
// `startDistance` deliberately begins the ray a little in front of the camera. Without that,
// the camera can end up "hitting" the voxel cell it is already standing inside, which feels like
// clicks do nothing because the edited block is not the one under the crosshair.
struct VoxelRaycaster {
    let startDistance: Float
    let maxDistance: Float
    let stepSize: Float

    init(startDistance: Float = 0.75, maxDistance: Float = 8.0, stepSize: Float = 0.05) {
        self.startDistance = startDistance
        self.maxDistance = maxDistance
        self.stepSize = stepSize
    }

    func raycast(camera: CameraState, in world: VoxelWorld) -> VoxelRaycastHit? {
        var previousEmptyCell: VoxelIndex?
        var lastVisitedCell: VoxelIndex?

        var distance = startDistance
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

public struct VoxelRaycastHit {
    public let solidCell: VoxelIndex
    public let placementCell: VoxelIndex?
}

public struct VoxelIndex: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let z: Int

    public init(x: Int, y: Int, z: Int) {
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
