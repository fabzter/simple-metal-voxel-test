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
    //
    // This must match the view-matrix convention used by the renderer. The renderer's view matrix
    // rotates the world by the camera angles, so the actual world-space forward ray uses the
    // inverse of that rotation. In practice that means pitch contributes with the opposite sign
    // from the naive `sin(pitch)` formula.
    public var forward: SIMD3<Float> {
        normalize(
            SIMD3<Float>(
                cos(pitch) * sin(yaw),
                -sin(pitch),
                -cos(pitch) * cos(yaw)))
    }
}
