import Testing
import simd

@testable import VoxelEngine

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

    @Test
    func sprintMultipliesMoveSpeed() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)
        let player = PlayerController(position: SIMD3<Float>(2, 0, 2), isGrounded: true)

        // Unsprinted displacement over 1 s at 6 m/s on flat ground.
        player.update(dt: 1.0, input: PlayerInput(moveForward: true), in: world)
        let unsprintedD = abs(player.position.z - 2)

        // Sprint displacement.
        let player2 = PlayerController(position: SIMD3<Float>(2, 0, 2), isGrounded: true)
        player2.update(dt: 1.0, input: PlayerInput(moveForward: true, sprint: true), in: world)
        let sprintedD = abs(player2.position.z - 2)

        let ratio = sprintedD / unsprintedD
        #expect(ratio > 1.5 && ratio < 1.7)
    }

    @Test
    func flyModeDisablesGravityAndAllowsVerticalControl() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)
        let player = PlayerController(position: SIMD3<Float>(2, 5, 2))

        player.toggleFlying()
        #expect(player.isFlying)

        // Fly up.
        player.update(dt: 0.5, input: PlayerInput(jump: true), in: world)
        #expect(player.position.y > 5)
        #expect(player.velocity.y > 0)

        // Fly down.
        let yAfterUp = player.position.y
        player.update(dt: 0.5, input: PlayerInput(descend: true), in: world)
        #expect(player.position.y < yAfterUp)
        #expect(player.velocity.y < 0)

        // No vertical input → velocity zero.
        player.update(dt: 0.5, input: PlayerInput(), in: world)
        #expect(player.velocity.y == 0)

        // Toggle off → gravity resumes.
        player.toggleFlying()
        #expect(!player.isFlying)
        let yBeforeFall = player.position.y
        player.update(dt: 0.1, input: PlayerInput(), in: world)
        #expect(player.position.y < yBeforeFall)
    }
}
