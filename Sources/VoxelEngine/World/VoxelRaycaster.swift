import simd

// A proper voxel DDA (Amanatides & Woo style) for block editing.
//
// The important idea is that we do not sample arbitrary points and round them. Instead we walk
// from voxel boundary to voxel boundary in the exact order the ray crosses the grid. That makes
// the selected block line up with the crosshair much more reliably.
struct VoxelRaycaster {
    let startDistance: Float
    let maxDistance: Float

    init(startDistance: Float = 0.75, maxDistance: Float = 8.0) {
        self.startDistance = startDistance
        self.maxDistance = maxDistance
    }

    func raycast(camera: CameraState, in world: VoxelWorld) -> VoxelRaycastHit? {
        raycast(
            origin: camera.position, direction: camera.forward, startDistance: startDistance,
            maxDistance: maxDistance, in: world)
    }

    func raycast(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        startDistance: Float = 0,
        maxDistance: Float,
        in world: VoxelWorld
    ) -> VoxelRaycastHit? {
        let normalizedDirection = normalize(direction)
        let startPoint = origin + normalizedDirection * startDistance + SIMD3<Float>(repeating: 0.5)

        var currentCell = VoxelIndex(pointInShiftedGrid: startPoint)
        var previousEmptyCell: VoxelIndex?

        let stepX = step(for: normalizedDirection.x)
        let stepY = step(for: normalizedDirection.y)
        let stepZ = step(for: normalizedDirection.z)

        var tMaxX = initialBoundaryDistance(
            origin: startPoint.x, direction: normalizedDirection.x, cell: currentCell.x)
        var tMaxY = initialBoundaryDistance(
            origin: startPoint.y, direction: normalizedDirection.y, cell: currentCell.y)
        var tMaxZ = initialBoundaryDistance(
            origin: startPoint.z, direction: normalizedDirection.z, cell: currentCell.z)

        let tDeltaX = boundaryStride(direction: normalizedDirection.x)
        let tDeltaY = boundaryStride(direction: normalizedDirection.y)
        let tDeltaZ = boundaryStride(direction: normalizedDirection.z)

        var traveled: Float = startDistance
        var hitFace: VoxelFace?

        while traveled <= maxDistance {
            if world.isSolid(x: currentCell.x, y: currentCell.y, z: currentCell.z) {
                return VoxelRaycastHit(
                    solidCell: currentCell,
                    placementCell: previousEmptyCell,
                    face: hitFace,
                    distance: traveled)
            }

            previousEmptyCell = currentCell

            if tMaxX <= tMaxY && tMaxX <= tMaxZ {
                currentCell = VoxelIndex(
                    x: currentCell.x + stepX, y: currentCell.y, z: currentCell.z)
                traveled = startDistance + tMaxX
                tMaxX += tDeltaX
                hitFace = stepX > 0 ? .left : .right
            } else if tMaxY <= tMaxX && tMaxY <= tMaxZ {
                currentCell = VoxelIndex(
                    x: currentCell.x, y: currentCell.y + stepY, z: currentCell.z)
                traveled = startDistance + tMaxY
                tMaxY += tDeltaY
                hitFace = stepY > 0 ? .bottom : .top
            } else {
                currentCell = VoxelIndex(
                    x: currentCell.x, y: currentCell.y, z: currentCell.z + stepZ)
                traveled = startDistance + tMaxZ
                tMaxZ += tDeltaZ
                hitFace = stepZ > 0 ? .back : .front
            }
        }

        return nil
    }

    private func step(for direction: Float) -> Int {
        if direction > 0 { return 1 }
        if direction < 0 { return -1 }
        return 0
    }

    private func initialBoundaryDistance(origin: Float, direction: Float, cell: Int) -> Float {
        guard abs(direction) > 0.0001 else {
            return .infinity
        }

        if direction > 0 {
            return (Float(cell + 1) - origin) / direction
        } else {
            return (origin - Float(cell)) / -direction
        }
    }

    private func boundaryStride(direction: Float) -> Float {
        guard abs(direction) > 0.0001 else {
            return .infinity
        }
        return 1.0 / abs(direction)
    }
}

public struct VoxelRaycastHit {
    public let solidCell: VoxelIndex
    public let placementCell: VoxelIndex?
    public let face: VoxelFace?
    public let distance: Float
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

    init(pointInShiftedGrid: SIMD3<Float>) {
        self.init(
            x: Int(floor(pointInShiftedGrid.x)),
            y: Int(floor(pointInShiftedGrid.y)),
            z: Int(floor(pointInShiftedGrid.z)))
    }
}

public enum VoxelFace: Sendable {
    case front
    case back
    case top
    case bottom
    case left
    case right

    public var label: String {
        switch self {
        case .front: return "front"
        case .back: return "back"
        case .top: return "top"
        case .bottom: return "bottom"
        case .left: return "left"
        case .right: return "right"
        }
    }

    public var normal: SIMD3<Float> {
        switch self {
        case .front: return SIMD3(0, 0, 1)
        case .back: return SIMD3(0, 0, -1)
        case .top: return SIMD3(0, 1, 0)
        case .bottom: return SIMD3(0, -1, 0)
        case .left: return SIMD3(-1, 0, 0)
        case .right: return SIMD3(1, 0, 0)
        }
    }

    public var opposite: VoxelFace {
        switch self {
        case .front: return .back
        case .back: return .front
        case .top: return .bottom
        case .bottom: return .top
        case .left: return .right
        case .right: return .left
        }
    }

    var normalIndex: SIMD3<Int> {
        switch self {
        case .front: return SIMD3(0, 0, 1)
        case .back: return SIMD3(0, 0, -1)
        case .top: return SIMD3(0, 1, 0)
        case .bottom: return SIMD3(0, -1, 0)
        case .left: return SIMD3(-1, 0, 0)
        case .right: return SIMD3(1, 0, 0)
        }
    }
}
