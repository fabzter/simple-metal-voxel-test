import simd

// The selection overlay now draws two things:
// 1. an outline around the selected face
// 2. a short line protruding along the face normal
//
// That extra normal line makes it much clearer which exact face will receive a placement.
struct SelectionHighlightMesh {
    let vertices: [SIMD3<Float>]

    init(cell: VoxelIndex, face: VoxelFace, inset: Float = 0.82, normalLength: Float = 0.45) {
        let x = Float(cell.x)
        let y = Float(cell.y)
        let z = Float(cell.z)

        let min = SIMD3<Float>(x - 0.5, y - 0.5, z - 0.5)
        let max = SIMD3<Float>(x + 0.5, y + 0.5, z + 0.5)

        let corners: [SIMD3<Float>]
        switch face {
        case .front:
            corners = [
                SIMD3(min.x, min.y, max.z + 0.01),
                SIMD3(max.x, min.y, max.z + 0.01),
                SIMD3(max.x, max.y, max.z + 0.01),
                SIMD3(min.x, max.y, max.z + 0.01),
            ]
        case .back:
            corners = [
                SIMD3(max.x, min.y, min.z - 0.01),
                SIMD3(min.x, min.y, min.z - 0.01),
                SIMD3(min.x, max.y, min.z - 0.01),
                SIMD3(max.x, max.y, min.z - 0.01),
            ]
        case .top:
            corners = [
                SIMD3(min.x, max.y + 0.01, max.z),
                SIMD3(max.x, max.y + 0.01, max.z),
                SIMD3(max.x, max.y + 0.01, min.z),
                SIMD3(min.x, max.y + 0.01, min.z),
            ]
        case .bottom:
            corners = [
                SIMD3(min.x, min.y - 0.01, min.z),
                SIMD3(max.x, min.y - 0.01, min.z),
                SIMD3(max.x, min.y - 0.01, max.z),
                SIMD3(min.x, min.y - 0.01, max.z),
            ]
        case .left:
            corners = [
                SIMD3(min.x - 0.01, min.y, min.z),
                SIMD3(min.x - 0.01, min.y, max.z),
                SIMD3(min.x - 0.01, max.y, max.z),
                SIMD3(min.x - 0.01, max.y, min.z),
            ]
        case .right:
            corners = [
                SIMD3(max.x + 0.01, min.y, max.z),
                SIMD3(max.x + 0.01, min.y, min.z),
                SIMD3(max.x + 0.01, max.y, min.z),
                SIMD3(max.x + 0.01, max.y, max.z),
            ]
        }

        let faceOutline = Self.rectangle(corners: corners, inset: inset)
        let center = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
        let normalEnd = center + face.normal * normalLength
        let normalLine = [center, normalEnd]
        vertices = faceOutline + normalLine
    }

    private static func rectangle(corners: [SIMD3<Float>], inset: Float) -> [SIMD3<Float>] {
        let center = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
        let adjusted = corners.map { mix($0, center, t: 1 - inset) }

        return [
            adjusted[0], adjusted[1],
            adjusted[1], adjusted[2],
            adjusted[2], adjusted[3],
            adjusted[3], adjusted[0],
        ]
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}
