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
                let maxY = terrainHeight(x: x, z: z, seedParameters: seedParameters)
                let clampedMaxY = min(maxY, world.gridSize - 1)

                guard clampedMaxY >= 0 else {
                    continue
                }

                for y in 0...clampedMaxY {
                    guard
                        !shouldCarveCave(
                            x: x, y: y, z: z, surfaceY: maxY, seedParameters: seedParameters)
                    else {
                        continue
                    }

                    world.setSolid(true, x: x, y: y, z: z)
                }
            }
        }
    }

    // Derive repeatable offsets and scale variations from the seed.
    private func parameters(from seed: UInt64) -> TerrainSeedParameters {
        var generator = SeededValueGenerator(state: seed)

        let xFrequencyScale = 0.85 + 0.3 * generator.nextUnitValue()
        let zFrequencyScale = 0.85 + 0.3 * generator.nextUnitValue()
        let xAmplitudeScale = 0.85 + 0.3 * generator.nextUnitValue()
        let zAmplitudeScale = 0.85 + 0.3 * generator.nextUnitValue()

        return TerrainSeedParameters(
            xFrequency: configuration.xFrequency * xFrequencyScale,
            zFrequency: configuration.zFrequency * zFrequencyScale,
            xAmplitude: configuration.xAmplitude * xAmplitudeScale,
            zAmplitude: configuration.zAmplitude * zAmplitudeScale,
            baseOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            ridgeOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            detailOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            caveOffset: SIMD3<Float>(
                generator.nextSignedValue() * 64,
                generator.nextSignedValue() * 64,
                generator.nextSignedValue() * 64),
            caveFrequency: 0.10 + 0.03 * generator.nextUnitValue(),
            caveVerticalFrequency: 0.12 + 0.04 * generator.nextUnitValue())
    }

    private func terrainHeight(x: Int, z: Int, seedParameters: TerrainSeedParameters) -> Int {
        let sample = SIMD2<Float>(Float(x), Float(z))
        let baseSample = SIMD2<Float>(
            sample.x * seedParameters.xFrequency,
            sample.y * seedParameters.zFrequency)

        let broadHills = fbm2(
            baseSample + seedParameters.baseOffset,
            seed: 0xA53C_9E12_D41B_A8C1,
            octaves: 4,
            lacunarity: 2.0,
            persistence: 0.5)
        let ridges = ridge(
            fbm2(
                baseSample * 2.1 + seedParameters.ridgeOffset,
                seed: 0x5B8D_80CE_A9D1_4F27,
                octaves: 3,
                lacunarity: 2.15,
                persistence: 0.55))
        let detail = fbm2(
            baseSample * 4.0 + seedParameters.detailOffset,
            seed: 0x94D0_49BB_1331_11EB,
            octaves: 2,
            lacunarity: 2.35,
            persistence: 0.6)

        let rollingHeight = (broadHills - 0.5) * (seedParameters.xAmplitude * 2.4)
        let ridgeHeight = ridges * (seedParameters.zAmplitude * 1.8)
        let detailHeight =
            (detail - 0.5) * min(seedParameters.xAmplitude, seedParameters.zAmplitude)

        return Int(
            round(Float(configuration.baseHeight) + rollingHeight + ridgeHeight + detailHeight))
    }

    private func shouldCarveCave(
        x: Int,
        y: Int,
        z: Int,
        surfaceY: Int,
        seedParameters: TerrainSeedParameters
    ) -> Bool {
        guard y > 4, y < surfaceY - 3 else {
            return false
        }

        let caveSample =
            SIMD3<Float>(
                Float(x) * seedParameters.caveFrequency,
                Float(y) * seedParameters.caveVerticalFrequency,
                Float(z) * seedParameters.caveFrequency
            ) + seedParameters.caveOffset

        let caveNoise = fbm3(
            caveSample,
            seed: 0x9E37_79B9_7F4A_7C15,
            octaves: 3,
            lacunarity: 2.0,
            persistence: 0.52)
        let cavernBias = ridge(
            fbm2(
                SIMD2<Float>(caveSample.x, caveSample.z) * 0.55,
                seed: 0xBF58_476D_1CE4_E5B9,
                octaves: 2,
                lacunarity: 2.0,
                persistence: 0.5))
        let depthBelowSurface = Float(surfaceY - y) / Float(max(surfaceY, 1))
        let threshold = 0.76 - cavernBias * 0.10

        return caveNoise > threshold && depthBelowSurface > 0.18
    }

    private func fbm2(
        _ point: SIMD2<Float>,
        seed: UInt64,
        octaves: Int,
        lacunarity: Float,
        persistence: Float
    ) -> Float {
        var amplitude: Float = 0.5
        var frequency: Float = 1.0
        var total: Float = 0
        var normalization: Float = 0

        for octave in 0..<octaves {
            total += amplitude * valueNoise2(point * frequency, seed: seed &+ UInt64(octave))
            normalization += amplitude
            frequency *= lacunarity
            amplitude *= persistence
        }

        return normalization > 0 ? total / normalization : 0
    }

    private func fbm3(
        _ point: SIMD3<Float>,
        seed: UInt64,
        octaves: Int,
        lacunarity: Float,
        persistence: Float
    ) -> Float {
        var amplitude: Float = 0.5
        var frequency: Float = 1.0
        var total: Float = 0
        var normalization: Float = 0

        for octave in 0..<octaves {
            total += amplitude * valueNoise3(point * frequency, seed: seed &+ UInt64(octave))
            normalization += amplitude
            frequency *= lacunarity
            amplitude *= persistence
        }

        return normalization > 0 ? total / normalization : 0
    }

    private func valueNoise2(_ point: SIMD2<Float>, seed: UInt64) -> Float {
        let x0 = Int(floor(point.x))
        let z0 = Int(floor(point.y))
        let tx = smoothstep(point.x - floor(point.x))
        let tz = smoothstep(point.y - floor(point.y))

        let v00 = randomUnitValue(x: x0, y: z0, z: 0, seed: seed)
        let v10 = randomUnitValue(x: x0 + 1, y: z0, z: 0, seed: seed)
        let v01 = randomUnitValue(x: x0, y: z0 + 1, z: 0, seed: seed)
        let v11 = randomUnitValue(x: x0 + 1, y: z0 + 1, z: 0, seed: seed)

        let a = lerp(v00, v10, t: tx)
        let b = lerp(v01, v11, t: tx)
        return lerp(a, b, t: tz)
    }

    private func valueNoise3(_ point: SIMD3<Float>, seed: UInt64) -> Float {
        let x0 = Int(floor(point.x))
        let y0 = Int(floor(point.y))
        let z0 = Int(floor(point.z))
        let tx = smoothstep(point.x - floor(point.x))
        let ty = smoothstep(point.y - floor(point.y))
        let tz = smoothstep(point.z - floor(point.z))

        let c000 = randomUnitValue(x: x0, y: y0, z: z0, seed: seed)
        let c100 = randomUnitValue(x: x0 + 1, y: y0, z: z0, seed: seed)
        let c010 = randomUnitValue(x: x0, y: y0 + 1, z: z0, seed: seed)
        let c110 = randomUnitValue(x: x0 + 1, y: y0 + 1, z: z0, seed: seed)
        let c001 = randomUnitValue(x: x0, y: y0, z: z0 + 1, seed: seed)
        let c101 = randomUnitValue(x: x0 + 1, y: y0, z: z0 + 1, seed: seed)
        let c011 = randomUnitValue(x: x0, y: y0 + 1, z: z0 + 1, seed: seed)
        let c111 = randomUnitValue(x: x0 + 1, y: y0 + 1, z: z0 + 1, seed: seed)

        let x00 = lerp(c000, c100, t: tx)
        let x10 = lerp(c010, c110, t: tx)
        let x01 = lerp(c001, c101, t: tx)
        let x11 = lerp(c011, c111, t: tx)
        let y0Mix = lerp(x00, x10, t: ty)
        let y1Mix = lerp(x01, x11, t: ty)
        return lerp(y0Mix, y1Mix, t: tz)
    }

    private func randomUnitValue(x: Int, y: Int, z: Int, seed: UInt64) -> Float {
        var value = seed
        value &+= UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        value &+= UInt64(bitPattern: Int64(y)) &* 0xBF58_476D_1CE4_E5B9
        value &+= UInt64(bitPattern: Int64(z)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(Double(value) / Double(UInt64.max))
    }

    private func ridge(_ value: Float) -> Float {
        1 - abs(2 * value - 1)
    }

    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    private func smoothstep(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }
}

private struct TerrainSeedParameters {
    let xFrequency: Float
    let zFrequency: Float
    let xAmplitude: Float
    let zAmplitude: Float
    let baseOffset: SIMD2<Float>
    let ridgeOffset: SIMD2<Float>
    let detailOffset: SIMD2<Float>
    let caveOffset: SIMD3<Float>
    let caveFrequency: Float
    let caveVerticalFrequency: Float
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

    mutating func nextSignedValue() -> Float {
        nextUnitValue() * 2 - 1
    }
}
