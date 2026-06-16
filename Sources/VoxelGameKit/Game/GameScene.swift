import simd

// `GameScene` is the high-level gameplay object for the demo.
//
// It owns the persistent simulation state that changes frame-to-frame:
// - the voxel world the player collides with and looks at
// - the player/controller state
//
// The renderer reads data from the scene, but the scene itself is independent of Metal.
// That separation keeps game logic testable without needing a GPU.
public final class GameScene {
    public let world: VoxelWorld
    public let player: PlayerController

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
    }

    // Advance one frame of game simulation.
    //
    // `lookDelta` is the accumulated mouse movement since the last frame.
    // `input` is the current keyboard/button state snapshot.
    public func update(dt: Float, input: PlayerInput, lookDelta: SIMD2<Float>) {
        player.rotateCamera(deltaX: lookDelta.x, deltaY: lookDelta.y)
        player.update(dt: dt, input: input, in: world)
    }
}
