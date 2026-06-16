import Foundation
import simd

// This type is responsible only for filling a `VoxelWorld` with solid cells.
// It does not know anything about rendering.
struct VoxelTerrainGenerator {
    let configuration: VoxelWorldConfiguration

    init(configuration: VoxelWorldConfiguration) {
        self.configuration = configuration
    }

    func populate(_ world: VoxelWorld) {
        let seedParameters = parameters(from: configuration.seed)

        for x in 0..<world.gridSize {
            for z in 0..<world.gridSize {
                let surfaceHeight =
                    sin(Float(x) * seedParameters.xFrequency + seedParameters.xPhase)
                    * seedParameters.xAmplitude
                    + cos(Float(z) * seedParameters.zFrequency + seedParameters.zPhase)
                    * seedParameters.zAmplitude

                let maxY = Int(surfaceHeight) + configuration.baseHeight

                for y in 0...maxY where y >= 0 && y < world.gridSize {
                    world.setSolid(true, x: x, y: y, z: z)
                }
            }
        }
    }

    // Derive a few repeatable wave parameters from the seed.
    // Same seed -> same hills.
    // Different seed -> same algorithm, but with shifted/scaled waves.
    private func parameters(from seed: UInt64) -> TerrainSeedParameters {
        var generator = SeededValueGenerator(state: seed)

        let xPhase = phase(from: generator.nextUnitValue())
        let zPhase = phase(from: generator.nextUnitValue())

        let xFrequencyScale = 0.85 + 0.3 * generator.nextUnitValue()
        let zFrequencyScale = 0.85 + 0.3 * generator.nextUnitValue()
        let xAmplitudeScale = 0.85 + 0.3 * generator.nextUnitValue()
        let zAmplitudeScale = 0.85 + 0.3 * generator.nextUnitValue()

        return TerrainSeedParameters(
            xPhase: xPhase,
            zPhase: zPhase,
            xFrequency: configuration.xFrequency * xFrequencyScale,
            zFrequency: configuration.zFrequency * zFrequencyScale,
            xAmplitude: configuration.xAmplitude * xAmplitudeScale,
            zAmplitude: configuration.zAmplitude * zAmplitudeScale)
    }

    private func phase(from unitValue: Float) -> Float {
        unitValue * Float.pi * 2
    }
}

private struct TerrainSeedParameters {
    let xPhase: Float
    let zPhase: Float
    let xFrequency: Float
    let zFrequency: Float
    let xAmplitude: Float
    let zAmplitude: Float
}

private struct SeededValueGenerator {
    var state: UInt64

    mutating func nextUnitValue() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)

        let fraction = Double(z) / Double(UInt64.max)
        return Float(fraction)
    }
}
