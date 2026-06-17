import simd

// `GameScene` is the high-level gameplay object for the demo.
//
// It owns the persistent simulation state that changes frame-to-frame:
// - the voxel world the player collides with and edits
// - the player/controller state
// - the currently targeted block under the crosshair
//
// The renderer reads data from the scene, but the scene itself is independent of Metal.
// That separation keeps game logic testable without needing a GPU.
public final class GameScene {
    public let world: VoxelWorld
    public let player: PlayerController

    private let raycaster = VoxelRaycaster()

    public private(set) var currentTarget: VoxelRaycastHit?

    public var camera: CameraState {
        player.camera
    }

    public init(
        gridSize: Int = 64,
        worldGeneration: VoxelWorld.Generation = .terrain(.default),
        player: PlayerController = PlayerController()
    ) {
        self.world = VoxelWorld(gridSize: gridSize, generation: worldGeneration)
        self.player = player
        self.currentTarget = raycaster.raycast(camera: player.camera, in: world)
    }

    // Advance one frame of game simulation.
    //
    // `lookDelta` is the accumulated mouse movement since the last frame.
    // `input` is the current keyboard/button state snapshot.
    // `editActions` are one-shot mouse actions such as block placement/removal.
    public func update(
        dt: Float,
        input: PlayerInput,
        lookDelta: SIMD2<Float>,
        editActions: [BlockEditAction] = []
    ) {
        player.rotateCamera(deltaX: lookDelta.x, deltaY: lookDelta.y)
        player.update(dt: dt, input: input, in: world)
        currentTarget = raycaster.raycast(camera: camera, in: world)

        for editAction in editActions {
            apply(editAction)
        }

        currentTarget = raycaster.raycast(camera: camera, in: world)
    }

    private func apply(_ editAction: BlockEditAction) {
        guard let hit = currentTarget else {
            return
        }

        switch editAction {
        case .remove:
            world.setSolid(false, x: hit.solidCell.x, y: hit.solidCell.y, z: hit.solidCell.z)
        case .place:
            guard let placementCell = hit.placementCell else {
                return
            }

            guard !placementWouldIntersectPlayer(placementCell) else {
                return
            }

            world.setSolid(true, x: placementCell.x, y: placementCell.y, z: placementCell.z)
        }
    }

    private func placementWouldIntersectPlayer(_ cell: VoxelIndex) -> Bool {
        let voxelMin = SIMD3<Float>(Float(cell.x) - 0.5, Float(cell.y) - 0.5, Float(cell.z) - 0.5)
        let voxelMax = SIMD3<Float>(Float(cell.x) + 0.5, Float(cell.y) + 0.5, Float(cell.z) + 0.5)

        let playerMin = SIMD3<Float>(
            player.position.x - player.playerRadius,
            player.position.y,
            player.position.z - player.playerRadius)
        let playerMax = SIMD3<Float>(
            player.position.x + player.playerRadius,
            player.position.y + player.playerHeight,
            player.position.z + player.playerRadius)

        let overlapsX = voxelMin.x <= playerMax.x && voxelMax.x >= playerMin.x
        let overlapsY = voxelMin.y <= playerMax.y && voxelMax.y >= playerMin.y
        let overlapsZ = voxelMin.z <= playerMax.z && voxelMax.z >= playerMin.z
        return overlapsX && overlapsY && overlapsZ
    }
}
