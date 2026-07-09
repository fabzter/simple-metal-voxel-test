import simd

struct Vertex {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let color: SIMD3<Float>
    let uv: SIMD2<Float>
    let materialMode: Float
}

struct Uniforms {
    let projection: float4x4
    let view: float4x4
    let materialDebugMode: Float
    let lodTintOverlayMode: Float
    let lodTintColor: SIMD4<Float>
    let highlightColor: SIMD4<Float>
    let fadeThreshold: Float  // 1.0 = fully drawn; < 1.0 = dither threshold for LOD crossfade

    // MARK: Atmosphere (appended)
    //
    // These mirror the same-named fields in the Metal `Uniforms` struct in
    // VoxelShaders.metal and MUST stay in the same order. Every field below is a
    // 16-byte-aligned simd type (float4 / float4x4), so Swift and Metal insert identical
    // padding after `fadeThreshold` and the two layouts match byte-for-byte.
    let inverseViewProjection: float4x4  // NDC -> world, for the sky's view ray
    let cameraPositionAndFog: SIMD4<Float>  // xyz = camera world position, w = fog density
    let sunDirection: SIMD4<Float>  // xyz = normalized direction toward the sun
    let sunColor: SIMD4<Float>  // rgb = sunlight / sun-disk color
    let skyZenithColor: SIMD4<Float>  // rgb = sky color straight up
    let skyHorizonColor: SIMD4<Float>  // rgb = horizon color (also the fog color)
    let groundColor: SIMD4<Float>  // rgb = below-horizon + downward ambient bounce
}

enum MaterialMode: Float {
    case flatColor = 0
    case textured = 1
}
