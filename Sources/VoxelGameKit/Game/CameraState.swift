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
}
