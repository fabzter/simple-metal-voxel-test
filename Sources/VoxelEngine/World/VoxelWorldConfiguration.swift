import Foundation

// This configuration describes how the procedural voxel terrain is generated.
// The current terrain uses layered deterministic noise:
// - a broad rolling base
// - a ridged detail layer
// - a cave-carving pass below the surface
//
// `xFrequency` and `zFrequency` control the horizontal sampling scale, while
// `xAmplitude` and `zAmplitude` shape the large and medium vertical variation.
public struct VoxelWorldConfiguration: Sendable, Equatable {
    public var seed: UInt64
    public var baseHeight: Int
    public var xFrequency: Float
    public var zFrequency: Float
    public var xAmplitude: Float
    public var zAmplitude: Float

    public init(
        seed: UInt64 = 0,
        baseHeight: Int = 18,
        xFrequency: Float = 0.018,
        zFrequency: Float = 0.018,
        xAmplitude: Float = 9.0,
        zAmplitude: Float = 7.0
    ) {
        self.seed = seed
        self.baseHeight = baseHeight
        self.xFrequency = xFrequency
        self.zFrequency = zFrequency
        self.xAmplitude = xAmplitude
        self.zAmplitude = zAmplitude
    }

    public static let `default` = VoxelWorldConfiguration()
}
