import simd

struct Vertex {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let color: SIMD3<Float>
}

struct Uniforms {
    let projection: float4x4
    let view: float4x4
}
