import simd

// One vertex for one triangle corner.
//
// - `position`: world-space corner position.
// - `normal`: face direction for simple lighting.
// - `color`: flat color or texture tint.
// - `uv`: normalized atlas coordinates when textured.
// - `materialMode`: 0 = flat color, 1 = texture sample.
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
    let padding: SIMD3<Float>
    let highlightColor: SIMD4<Float>
}

enum MaterialMode: Float {
    case flatColor = 0
    case textured = 1
}
