import Foundation

// This configuration describes how the procedural voxel terrain is generated.
// The terrain here is just the sum of two waves:
// - one sine wave varying along X
// - one cosine wave varying along Z
//
// `seed` does not create random caves or noise yet. Instead it deterministically shifts
// the phase of those waves so the same seed always produces the same terrain and a
// different seed moves the hills into a different arrangement.
public struct VoxelWorldConfiguration: Sendable, Equatable {
    public var seed: UInt64
    public var baseHeight: Int
    public var xFrequency: Float
    public var zFrequency: Float
    public var xAmplitude: Float
    public var zAmplitude: Float

    public init(
        seed: UInt64 = 0,
        baseHeight: Int = 15,
        xFrequency: Float = 0.2,
        zFrequency: Float = 0.2,
        xAmplitude: Float = 4.0,
        zAmplitude: Float = 3.0
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
