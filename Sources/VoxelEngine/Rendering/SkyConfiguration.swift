import simd

/// Describes the look of the sky and sunlight for a frame.
///
/// This is deliberately a small bag of colors and one direction so the "feel" of a
/// scene's atmosphere can be tuned in one place — the same idea as
/// `CameraConfiguration` for looking around. The renderer feeds these values to the
/// shaders, which use them for three cheap effects:
///
/// 1. A full-screen **gradient sky** (horizon → zenith) with a soft sun disk.
/// 2. **Hemispheric ambient light** — surfaces facing up catch sky color, surfaces
///    facing down catch a darker ground bounce — plus a warm directional sun term.
/// 3. **Distance fog** that melts far terrain into the horizon color. Besides looking
///    nice, this hides the pop where distant chunks switch to coarser LOD, so it
///    complements the level-of-detail system instead of fighting it.
///
/// Everything here is per-vertex or a few ALU ops per pixel — no extra passes over
/// geometry, no textures — so it stays true to the project's resource-efficient soul.
public struct SkyConfiguration: Sendable, Equatable {
    /// Normalized direction pointing **toward** the sun (surface → sun). Used both for
    /// the sky's sun disk and for diffuse lighting.
    public var sunDirection: SIMD3<Float>
    /// Color/intensity of direct sunlight and the sun disk in the sky.
    public var sunColor: SIMD3<Float>
    /// Sky color straight up.
    public var zenithColor: SIMD3<Float>
    /// Sky color at the horizon. Also used as the distance-fog color so geometry fades
    /// into the sky seamlessly.
    public var horizonColor: SIMD3<Float>
    /// Color below the horizon and the ambient bounce reaching downward-facing surfaces.
    public var groundColor: SIMD3<Float>
    /// Exponential-squared fog density. Larger = thicker fog / shorter view. `0` disables
    /// fog. Tuned so nearby blocks stay crisp while the far world dissolves into the sky.
    public var fogDensity: Float

    public init(
        sunDirection: SIMD3<Float> = SIMD3<Float>(0.35, 0.82, 0.45),
        sunColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.96, 0.88),
        zenithColor: SIMD3<Float> = SIMD3<Float>(0.30, 0.52, 0.92),
        horizonColor: SIMD3<Float> = SIMD3<Float>(0.72, 0.83, 0.92),
        groundColor: SIMD3<Float> = SIMD3<Float>(0.34, 0.30, 0.26),
        fogDensity: Float = 0.0045
    ) {
        // Guard against a zero vector so `normalize` in the shader never sees NaNs.
        let length = simd_length(sunDirection)
        self.sunDirection = length > 0 ? sunDirection / length : SIMD3<Float>(0, 1, 0)
        self.sunColor = sunColor
        self.zenithColor = zenithColor
        self.horizonColor = horizonColor
        self.groundColor = groundColor
        self.fogDensity = max(0, fogDensity)
    }

    /// A bright, calm clear-afternoon sky. The engine looks good with no configuration;
    /// the demo can override this for a different mood.
    public static let `default` = SkyConfiguration()
}
