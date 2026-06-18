import simd

public final class GameScene {
    public let world: VoxelWorld
    public let player: PlayerController

    private let raycaster = VoxelRaycaster()

    public private(set) var currentTarget: VoxelRaycastHit?
    public private(set) var currentEditFeedback: EditFeedback?
    public var selectedPlacementMaterial: BlockMaterialType = .grass

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

    public func update(
        dt: Float,
        input: PlayerInput,
        lookDelta: SIMD2<Float>,
        editActions: [BlockEditAction] = []
    ) {
        player.rotateCamera(deltaX: lookDelta.x, deltaY: lookDelta.y)
        player.update(dt: dt, input: input, in: world)
        currentTarget = raycaster.raycast(camera: camera, in: world)
        advanceEditFeedback(dt: dt)

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
            currentEditFeedback = EditFeedback(kind: .remove, hit: hit)

        case .place:
            let placementCell = hit.placementCell ?? inferredPlacementCell(from: hit)

            guard !placementWouldIntersectPlayer(placementCell) else {
                return
            }

            world.setSolid(
                true,
                x: placementCell.x,
                y: placementCell.y,
                z: placementCell.z,
                material: selectedPlacementMaterial)

            let placementFace = hit.face?.opposite
            let placementHit = VoxelRaycastHit(
                solidCell: placementCell,
                placementCell: hit.solidCell,
                face: placementFace,
                distance: hit.distance)
            currentEditFeedback = EditFeedback(kind: .place, hit: placementHit)
        }
    }

    private func inferredPlacementCell(from hit: VoxelRaycastHit) -> VoxelIndex {
        guard let face = hit.face else {
            return hit.solidCell
        }

        let offset = face.normalIndex
        return VoxelIndex(
            x: hit.solidCell.x + offset.x,
            y: hit.solidCell.y + offset.y,
            z: hit.solidCell.z + offset.z)
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

    private func advanceEditFeedback(dt: Float) {
        guard var currentEditFeedback else {
            return
        }

        currentEditFeedback.remainingTime -= dt
        self.currentEditFeedback = currentEditFeedback.remainingTime > 0 ? currentEditFeedback : nil
    }
}
