import Testing
import simd

@testable import VoxelGameKit

struct PlayerControllerTests {
    @Test
    func playerFallsToGroundPlane() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)
        let player = PlayerController(position: SIMD3<Float>(2, 3, 2))

        for _ in 0..<180 {
            player.update(dt: 1.0 / 60.0, input: PlayerInput(), in: world)
        }

        #expect(player.isGrounded)
        #expect(abs(player.position.y) < 0.0001)
        #expect(abs(player.velocity.y) < 0.0001)
    }

    @Test
    func jumpAppliesUpwardVelocityWhenGrounded() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)
        let player = PlayerController(position: SIMD3<Float>(2, 0, 2), isGrounded: true)

        player.update(dt: 1.0 / 60.0, input: PlayerInput(jump: true), in: world)

        #expect(!player.isGrounded)
        #expect(player.velocity.y > 0)
        #expect(player.position.y > 0)
    }

    @Test
    func wallCollisionStopsHorizontalMovement() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)
        world.setSolid(true, x: 2, y: 0, z: 1)
        world.setSolid(true, x: 2, y: 1, z: 1)

        let player = PlayerController(
            position: SIMD3<Float>(1.25, 0, 1.5),
            isGrounded: true)

        player.update(
            dt: 0.25,
            input: PlayerInput(moveRight: true),
            in: world)

        #expect(abs(player.position.x - 1.25) < 0.0001)
        #expect(abs(player.velocity.x) < 0.0001)
    }
}
