import simd

struct SelectionHighlightMesh {
    let vertices: [SIMD3<Float>]

    init(cell: VoxelIndex, face: VoxelFace, inset: Float = 0.503) {
        let x = Float(cell.x)
        let y = Float(cell.y)
        let z = Float(cell.z)

        let min = SIMD3<Float>(x - 0.5, y - 0.5, z - 0.5)
        let max = SIMD3<Float>(x + 0.5, y + 0.5, z + 0.5)

        switch face {
        case .front:
            vertices = Self.rectangle(
                a: SIMD3(min.x, min.y, max.z + 0.01),
                b: SIMD3(max.x, min.y, max.z + 0.01),
                c: SIMD3(max.x, max.y, max.z + 0.01),
                d: SIMD3(min.x, max.y, max.z + 0.01),
                inset: inset)
        case .back:
            vertices = Self.rectangle(
                a: SIMD3(max.x, min.y, min.z - 0.01),
                b: SIMD3(min.x, min.y, min.z - 0.01),
                c: SIMD3(min.x, max.y, min.z - 0.01),
                d: SIMD3(max.x, max.y, min.z - 0.01),
                inset: inset)
        case .top:
            vertices = Self.rectangle(
                a: SIMD3(min.x, max.y + 0.01, max.z),
                b: SIMD3(max.x, max.y + 0.01, max.z),
                c: SIMD3(max.x, max.y + 0.01, min.z),
                d: SIMD3(min.x, max.y + 0.01, min.z),
                inset: inset)
        case .bottom:
            vertices = Self.rectangle(
                a: SIMD3(min.x, min.y - 0.01, min.z),
                b: SIMD3(max.x, min.y - 0.01, min.z),
                c: SIMD3(max.x, min.y - 0.01, max.z),
                d: SIMD3(min.x, min.y - 0.01, max.z),
                inset: inset)
        case .left:
            vertices = Self.rectangle(
                a: SIMD3(min.x - 0.01, min.y, min.z),
                b: SIMD3(min.x - 0.01, min.y, max.z),
                c: SIMD3(min.x - 0.01, max.y, max.z),
                d: SIMD3(min.x - 0.01, max.y, min.z),
                inset: inset)
        case .right:
            vertices = Self.rectangle(
                a: SIMD3(max.x + 0.01, min.y, max.z),
                b: SIMD3(max.x + 0.01, min.y, min.z),
                c: SIMD3(max.x + 0.01, max.y, min.z),
                d: SIMD3(max.x + 0.01, max.y, max.z),
                inset: inset)
        }
    }

    private static func rectangle(
        a: SIMD3<Float>,
        b: SIMD3<Float>,
        c: SIMD3<Float>,
        d: SIMD3<Float>,
        inset: Float
    ) -> [SIMD3<Float>] {
        let center = (a + b + c + d) / 4.0
        let a2 = mix(a, center, t: 1 - inset)
        let b2 = mix(b, center, t: 1 - inset)
        let c2 = mix(c, center, t: 1 - inset)
        let d2 = mix(d, center, t: 1 - inset)

        return [a2, b2, b2, c2, c2, d2, d2, a2]
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}
