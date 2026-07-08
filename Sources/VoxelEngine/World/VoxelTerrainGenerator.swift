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

        let xFrequencyScale = 0.92 + 0.16 * generator.nextUnitValue()
        let zFrequencyScale = 0.92 + 0.16 * generator.nextUnitValue()
        let xAmplitudeScale = 0.9 + 0.2 * generator.nextUnitValue()
        let zAmplitudeScale = 0.9 + 0.2 * generator.nextUnitValue()

        return TerrainSeedParameters(
            xFrequency: configuration.xFrequency * xFrequencyScale,
            zFrequency: configuration.zFrequency * zFrequencyScale,
            xAmplitude: configuration.xAmplitude * xAmplitudeScale,
            zAmplitude: configuration.zAmplitude * zAmplitudeScale,
            broadOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            biomeOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            plainsOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            hillsOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            mountainOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            ridgeOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            detailOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            terrainWarpOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            caveOffset: SIMD3<Float>(
                generator.nextSignedValue() * 64,
                generator.nextSignedValue() * 64,
                generator.nextSignedValue() * 64),
            caveRegionOffset: SIMD2<Float>(
                generator.nextSignedValue() * 64, generator.nextSignedValue() * 64),
            caveWarpOffset: SIMD3<Float>(
                generator.nextSignedValue() * 64,
                generator.nextSignedValue() * 64,
                generator.nextSignedValue() * 64),
            caveFrequency: 0.075 + 0.015 * generator.nextUnitValue(),
            caveVerticalFrequency: 0.085 + 0.015 * generator.nextUnitValue())
    }

    private func terrainHeight(x: Int, z: Int, seedParameters: TerrainSeedParameters) -> Int {
        let sample = SIMD2<Float>(Float(x), Float(z))
        let warpedSample =
            sample
            + vectorWarp2(
                sample * min(seedParameters.xFrequency, seedParameters.zFrequency) * 0.55
                    + seedParameters.terrainWarpOffset,
                seedX: 0xA53C_9E12_D41B_A8C1,
                seedY: 0xBF58_476D_1CE4_E5B9,
                magnitude: 18)
        let baseSample = SIMD2<Float>(
            warpedSample.x * seedParameters.xFrequency,
            warpedSample.y * seedParameters.zFrequency)

        let biomeNoise = fbm2(
            baseSample * 0.26 + seedParameters.biomeOffset,
            seed: 0x5B8D_80CE_A9D1_4F27,
            octaves: 3,
            lacunarity: 2.0,
            persistence: 0.5)
        let hilliness = smoothRange(0.58, 0.84, biomeNoise)
        let mountainMask = pow(
            smoothRange(
                0.70,
                0.92,
                fbm2(
                    baseSample * 0.34 + seedParameters.mountainOffset,
                    seed: 0x9E37_79B9_7F4A_7C15,
                    octaves: 3,
                    lacunarity: 2.0,
                    persistence: 0.5)),
            1.35)

        let broadShape = fbm2(
            baseSample * 0.42 + seedParameters.broadOffset,
            seed: 0xC13F_A9A9_02A6_328F,
            octaves: 4,
            lacunarity: 2.0,
            persistence: 0.5)
        let plainsNoise = fbm2(
            baseSample * 0.82 + seedParameters.plainsOffset,
            seed: 0x1656_67B1_9E37_79F9,
            octaves: 3,
            lacunarity: 2.0,
            persistence: 0.5)
        let rollingHills = fbm2(
            baseSample * 1.15 + seedParameters.hillsOffset,
            seed: 0x94D0_49BB_1331_11EB,
            octaves: 4,
            lacunarity: 2.05,
            persistence: 0.52)
        let ridgeNoise = ridge(
            fbm2(
                baseSample * 1.75 + seedParameters.ridgeOffset,
                seed: 0xBF58_476D_1CE4_E5B9,
                octaves: 3,
                lacunarity: 2.1,
                persistence: 0.56))
        let detail = fbm2(
            baseSample * 3.2 + seedParameters.detailOffset,
            seed: 0x632B_E59B_D9B4_E019,
            octaves: 2,
            lacunarity: 2.25,
            persistence: 0.55)

        let plainsHeight =
            Float(configuration.baseHeight)
            + (broadShape - 0.5) * (seedParameters.xAmplitude * 0.75)
            + (plainsNoise - 0.5) * (seedParameters.zAmplitude * 0.55)

        let hillsHeight =
            Float(configuration.baseHeight)
            + (broadShape - 0.5) * (seedParameters.xAmplitude * 1.65)
            + (rollingHills - 0.5) * (seedParameters.zAmplitude * 1.45)
            + ridgeNoise * (seedParameters.zAmplitude * 1.2 + mountainMask * 4.5)

        let blendedHeight = lerp(plainsHeight, hillsHeight, t: hilliness)
        let detailHeight =
            (detail - 0.5)
            * lerp(
                0.45, min(seedParameters.xAmplitude, seedParameters.zAmplitude) * 0.65, t: hilliness
            )
        let mountainLift = mountainMask * (seedParameters.zAmplitude * 2.4)

        return Int(round(blendedHeight + detailHeight + mountainLift))
    }

    private func shouldCarveCave(
        x: Int,
        y: Int,
        z: Int,
        surfaceY: Int,
        seedParameters: TerrainSeedParameters
    ) -> Bool {
        guard y > 4, y < surfaceY - 2 else {
            return false
        }

        let depthBelowSurface = Float(surfaceY - y) / Float(max(surfaceY, 1))
        let caveRegion = smoothRange(
            0.52,
            0.86,
            fbm2(
                SIMD2<Float>(Float(x), Float(z))
                    * min(seedParameters.xFrequency, seedParameters.zFrequency) * 0.75
                    + seedParameters.caveRegionOffset,
                seed: 0xD6E8_FD50_76A3_9B25,
                octaves: 3,
                lacunarity: 2.0,
                persistence: 0.5))

        guard caveRegion > 0.08 || depthBelowSurface > 0.30 else {
            return false
        }

        let caveBase = SIMD3<Float>(
            Float(x) * seedParameters.caveFrequency,
            Float(y) * seedParameters.caveVerticalFrequency,
            Float(z) * seedParameters.caveFrequency)
        let warpedCaveSample =
            caveBase
            + vectorWarp3(
                caveBase * 0.7 + seedParameters.caveWarpOffset,
                seedX: 0x9E37_79B9_7F4A_7C15,
                seedY: 0xBF58_476D_1CE4_E5B9,
                seedZ: 0x94D0_49BB_1331_11EB,
                magnitude: 0.9)
            + seedParameters.caveOffset

        let tunnelNoise = abs(
            fbm3(
                warpedCaveSample,
                seed: 0x632B_E59B_D9B4_E019,
                octaves: 3,
                lacunarity: 2.0,
                persistence: 0.5) - 0.5)
        let chamberNoise = fbm3(
            warpedCaveSample * 0.58,
            seed: 0x8CB9_2BA7_2F3D_8DD7,
            octaves: 2,
            lacunarity: 2.0,
            persistence: 0.52)
        let entranceNoise = ridge(
            fbm2(
                SIMD2<Float>(warpedCaveSample.x, warpedCaveSample.z) * 0.9,
                seed: 0x1656_67B1_9E37_79F9,
                octaves: 2,
                lacunarity: 2.0,
                persistence: 0.5))

        let tunnelWidth = lerp(0.032, 0.085, t: caveRegion * 0.75 + depthBelowSurface * 0.25)
        let chamberThreshold = 0.84 - caveRegion * 0.16 - depthBelowSurface * 0.08

        let carveTunnel = tunnelNoise < tunnelWidth && chamberNoise > 0.38
        let carveChamber = chamberNoise > chamberThreshold && depthBelowSurface > 0.22
        let carveEntrance =
            tunnelNoise < tunnelWidth * 0.85
            && entranceNoise > 0.58
            && caveRegion > 0.45
            && depthBelowSurface > 0.08

        return carveTunnel || carveChamber || carveEntrance
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

    private func vectorWarp2(
        _ point: SIMD2<Float>,
        seedX: UInt64,
        seedY: UInt64,
        magnitude: Float
    ) -> SIMD2<Float> {
        let x = valueNoise2(point, seed: seedX) * 2 - 1
        let y = valueNoise2(point, seed: seedY) * 2 - 1
        return SIMD2<Float>(x, y) * magnitude
    }

    private func vectorWarp3(
        _ point: SIMD3<Float>,
        seedX: UInt64,
        seedY: UInt64,
        seedZ: UInt64,
        magnitude: Float
    ) -> SIMD3<Float> {
        let x = valueNoise3(point, seed: seedX) * 2 - 1
        let y = valueNoise3(point, seed: seedY) * 2 - 1
        let z = valueNoise3(point, seed: seedZ) * 2 - 1
        return SIMD3<Float>(x, y, z) * magnitude
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

    private func smoothRange(_ lowerBound: Float, _ upperBound: Float, _ value: Float) -> Float {
        guard upperBound > lowerBound else {
            return value >= upperBound ? 1 : 0
        }

        let normalized = clamp((value - lowerBound) / (upperBound - lowerBound), lower: 0, upper: 1)
        return smoothstep(normalized)
    }

    private func clamp(_ value: Float, lower: Float, upper: Float) -> Float {
        max(lower, min(upper, value))
    }
}

private struct TerrainSeedParameters {
    let xFrequency: Float
    let zFrequency: Float
    let xAmplitude: Float
    let zAmplitude: Float
    let broadOffset: SIMD2<Float>
    let biomeOffset: SIMD2<Float>
    let plainsOffset: SIMD2<Float>
    let hillsOffset: SIMD2<Float>
    let mountainOffset: SIMD2<Float>
    let ridgeOffset: SIMD2<Float>
    let detailOffset: SIMD2<Float>
    let terrainWarpOffset: SIMD2<Float>
    let caveOffset: SIMD3<Float>
    let caveRegionOffset: SIMD2<Float>
    let caveWarpOffset: SIMD3<Float>
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
