import simd

struct SelectionHighlightMesh {
    let vertices: [SIMD3<Float>]

    init(cell: VoxelIndex, inset: Float = 0.53) {
        let x = Float(cell.x)
        let y = Float(cell.y)
        let z = Float(cell.z)

        let min = SIMD3<Float>(x - inset, y - inset, z - inset)
        let max = SIMD3<Float>(x + inset, y + inset, z + inset)

        vertices = [
            SIMD3(min.x, min.y, min.z), SIMD3(max.x, min.y, min.z),
            SIMD3(max.x, min.y, min.z), SIMD3(max.x, max.y, min.z),
            SIMD3(max.x, max.y, min.z), SIMD3(min.x, max.y, min.z),
            SIMD3(min.x, max.y, min.z), SIMD3(min.x, min.y, min.z),

            SIMD3(min.x, min.y, max.z), SIMD3(max.x, min.y, max.z),
            SIMD3(max.x, min.y, max.z), SIMD3(max.x, max.y, max.z),
            SIMD3(max.x, max.y, max.z), SIMD3(min.x, max.y, max.z),
            SIMD3(min.x, max.y, max.z), SIMD3(min.x, min.y, max.z),

            SIMD3(min.x, min.y, min.z), SIMD3(min.x, min.y, max.z),
            SIMD3(max.x, min.y, min.z), SIMD3(max.x, min.y, max.z),
            SIMD3(max.x, max.y, min.z), SIMD3(max.x, max.y, max.z),
            SIMD3(min.x, max.y, min.z), SIMD3(min.x, max.y, max.z),
        ]
    }
}
