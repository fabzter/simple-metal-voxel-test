import simd

public struct CameraState: Sendable {
    public var position: SIMD3<Float>
    public var yaw: Float
    public var pitch: Float

    public init(position: SIMD3<Float>, yaw: Float, pitch: Float) {
        self.position = position
        self.yaw = yaw
        self.pitch = pitch
    }

    // The normalized forward direction of the camera in world space.
    // This is the direction we use both for movement-relative aiming and for editing rays.
    public var forward: SIMD3<Float> {
        normalize(
            SIMD3<Float>(
                cos(pitch) * sin(yaw),
                sin(pitch),
                -cos(pitch) * cos(yaw)))
    }
}
