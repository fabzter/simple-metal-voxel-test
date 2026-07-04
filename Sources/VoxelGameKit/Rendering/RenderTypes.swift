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
}

enum MaterialMode: Float {
    case flatColor = 0
    case textured = 1
}
