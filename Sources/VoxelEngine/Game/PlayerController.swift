import simd

public final class PlayerController {
    public let gravity: Float
    public let jumpSpeed: Float
    public let moveSpeed: Float
    /// How quickly walking velocity eases toward the target (units: 1/second). Higher =
    /// snappier. The easing saturates for large simulation steps, so it never changes
    /// behavior for big `dt` values (e.g. tests) — only smooths real per-frame motion.
    public let groundAcceleration: Float
    public let playerHeight: Float
    public let playerRadius: Float
    public var cameraConfiguration: CameraConfiguration

    public private(set) var position: SIMD3<Float>
    public private(set) var velocity: SIMD3<Float>
    public private(set) var isGrounded: Bool
    public private(set) var isFlying: Bool
    public private(set) var cameraYaw: Float
    public private(set) var cameraPitch: Float

    public var camera: CameraState {
        CameraState(
            position: position + SIMD3<Float>(0, cameraConfiguration.eyeHeight, 0),
            yaw: cameraYaw,
            pitch: cameraPitch)
    }

    public init(
        position: SIMD3<Float> = SIMD3<Float>(32, 45, 32),
        velocity: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        isGrounded: Bool = false,
        cameraYaw: Float = 0.0,
        cameraPitch: Float = -0.2,
        isFlying: Bool = false,
        gravity: Float = -25.0,
        jumpSpeed: Float = 9.0,
        moveSpeed: Float = 6.0,
        groundAcceleration: Float = 12.0,
        playerHeight: Float = 1.8,
        playerRadius: Float = 0.3,
        cameraConfiguration: CameraConfiguration = .default
    ) {
        self.position = position
        self.velocity = velocity
        self.isGrounded = isGrounded
        self.cameraYaw = cameraYaw
        self.cameraPitch = cameraPitch
        self.gravity = gravity
        self.jumpSpeed = jumpSpeed
        self.moveSpeed = moveSpeed
        self.groundAcceleration = groundAcceleration
        self.playerHeight = playerHeight
        self.playerRadius = playerRadius
        self.cameraConfiguration = cameraConfiguration
        self.isFlying = isFlying
    }

    public func rotateCamera(deltaX: Float, deltaY: Float) {
        cameraYaw += deltaX * cameraConfiguration.lookSensitivity
        let pitchDirection: Float = cameraConfiguration.invertLookY ? -1 : 1
        cameraPitch += deltaY * cameraConfiguration.lookSensitivity * pitchDirection
        cameraPitch = min(
            max(cameraPitch, cameraConfiguration.minimumPitch),
            cameraConfiguration.maximumPitch)
    }

    public func toggleFlying() {
        isFlying.toggle()
        velocity.y = 0  // No residual plummet on enable, natural fall on disable
    }

    public func update(dt: Float, input: PlayerInput, in world: VoxelWorld) {
        if isFlying {
            let flySpeed = moveSpeed * 2.5
            var wishVelocity = SIMD3<Float>(0, 0, 0)
            let forward = SIMD3<Float>(sin(cameraYaw), 0, -cos(cameraYaw))
            let right = SIMD3<Float>(cos(cameraYaw), 0, sin(cameraYaw))

            if input.moveForward { wishVelocity += forward }
            if input.moveBackward { wishVelocity -= forward }
            if input.moveLeft { wishVelocity -= right }
            if input.moveRight { wishVelocity += right }
            if length(wishVelocity) > 0 { wishVelocity = normalize(wishVelocity) * flySpeed }

            velocity.x = wishVelocity.x
            velocity.z = wishVelocity.z
            velocity.y = input.jump ? flySpeed : (input.descend ? -flySpeed : 0)

            // Same per-axis collide-and-cancel as walking; blocks still stop the player while flying.
            var nextPosition = position
            nextPosition.x += velocity.x * dt
            if collides(at: nextPosition, in: world) {
                nextPosition.x = position.x
                velocity.x = 0
            }
            nextPosition.z += velocity.z * dt
            if collides(at: nextPosition, in: world) {
                nextPosition.z = position.z
                velocity.z = 0
            }
            nextPosition.y += velocity.y * dt
            if collides(at: nextPosition, in: world) {
                nextPosition.y = position.y
                velocity.y = 0
            }
            position = nextPosition
            isGrounded = false
            return
        }

        if !isGrounded {
            velocity.y += gravity * dt
        }

        var inputVelocity = SIMD3<Float>(0, 0, 0)
        let forward = SIMD3<Float>(sin(cameraYaw), 0, -cos(cameraYaw))
        let right = SIMD3<Float>(cos(cameraYaw), 0, sin(cameraYaw))

        if input.moveForward { inputVelocity += forward }
        if input.moveBackward { inputVelocity -= forward }
        if input.moveLeft { inputVelocity -= right }
        if input.moveRight { inputVelocity += right }

        if length(inputVelocity) > 0 {
            inputVelocity = normalize(inputVelocity) * (moveSpeed * (input.sprint ? 1.6 : 1.0))
        }

        // Ease horizontal velocity toward the target so starting and stopping feel smooth
        // instead of instant. `min(1, ...)` saturates for large dt, keeping behavior
        // identical for big simulation steps while smoothing real ~16 ms frames.
        let accelerationFactor = min(1, groundAcceleration * dt)
        velocity.x += (inputVelocity.x - velocity.x) * accelerationFactor
        velocity.z += (inputVelocity.z - velocity.z) * accelerationFactor

        if input.jump && isGrounded {
            velocity.y = jumpSpeed
            isGrounded = false
        }

        var nextPosition = position
        nextPosition.x += velocity.x * dt
        if collides(at: nextPosition, in: world) {
            nextPosition.x = position.x
            velocity.x = 0
        }

        nextPosition.z += velocity.z * dt
        if collides(at: nextPosition, in: world) {
            nextPosition.z = position.z
            velocity.z = 0
        }

        isGrounded = false
        var verticalTestPosition = nextPosition
        verticalTestPosition.y += velocity.y * dt

        if collides(at: verticalTestPosition, in: world) {
            if velocity.y <= 0 {
                isGrounded = true
                let minY = Int(floor(verticalTestPosition.y))
                verticalTestPosition.y = Float(minY + 1)
            } else {
                let maxY = Int(floor(verticalTestPosition.y + playerHeight))
                verticalTestPosition.y = Float(maxY) - playerHeight - 0.001
            }

            velocity.y = 0
        } else if isStandingOnGround(at: verticalTestPosition, in: world) {
            isGrounded = true
            velocity.y = 0
        }

        position = verticalTestPosition
    }

    func collides(at position: SIMD3<Float>, in world: VoxelWorld) -> Bool {
        let minX = Int(floor(position.x - playerRadius))
        let maxX = Int(floor(position.x + playerRadius))
        let minY = Int(floor(position.y))
        let maxY = Int(floor(position.y + playerHeight))
        let minZ = Int(floor(position.z - playerRadius))
        let maxZ = Int(floor(position.z + playerRadius))

        for x in minX...maxX {
            for y in minY...maxY {
                for z in minZ...maxZ where world.isSolid(x: x, y: y, z: z) {
                    return true
                }
            }
        }

        return false
    }

    private func isStandingOnGround(at position: SIMD3<Float>, in world: VoxelWorld) -> Bool {
        let probeOffset: Float = 0.05
        let probePosition = SIMD3<Float>(position.x, position.y - probeOffset, position.z)
        return collides(at: probePosition, in: world)
    }
}
