import simd

struct VoxelMesher {
    func makeWorldMesh(for world: VoxelWorld) -> WorldMesh {
        var meshVertices: [Vertex] = []

        for x in 0..<world.gridSize {
            for y in 0..<world.gridSize {
                for z in 0..<world.gridSize where world.isSolid(x: x, y: y, z: z) {
                    let position = SIMD3<Float>(Float(x), Float(y), Float(z))
                    let color = color(for: y)

                    if !world.isSolid(x: x, y: y + 1, z: z) {
                        appendFace(to: &meshVertices, offset: position, faceIndex: 2, color: color)
                    }
                    if !world.isSolid(x: x, y: y - 1, z: z) {
                        appendFace(to: &meshVertices, offset: position, faceIndex: 3, color: color)
                    }
                    if !world.isSolid(x: x, y: y, z: z + 1) {
                        appendFace(to: &meshVertices, offset: position, faceIndex: 0, color: color)
                    }
                    if !world.isSolid(x: x, y: y, z: z - 1) {
                        appendFace(to: &meshVertices, offset: position, faceIndex: 1, color: color)
                    }
                    if !world.isSolid(x: x + 1, y: y, z: z) {
                        appendFace(to: &meshVertices, offset: position, faceIndex: 4, color: color)
                    }
                    if !world.isSolid(x: x - 1, y: y, z: z) {
                        appendFace(to: &meshVertices, offset: position, faceIndex: 5, color: color)
                    }
                }
            }
        }

        return WorldMesh(vertices: meshVertices)
    }

    private func color(for y: Int) -> SIMD3<Float> {
        if y > 15 {
            return SIMD3<Float>(0.2, 0.8, 0.2)
        }

        if y > 12 {
            return SIMD3<Float>(0.5, 0.3, 0.1)
        }

        return SIMD3<Float>(0.5, 0.5, 0.5)
    }

    private func appendFace(
        to meshVertices: inout [Vertex],
        offset: SIMD3<Float>,
        faceIndex: Int,
        color: SIMD3<Float>
    ) {
        let faces: [[SIMD3<Float>]] = [
            [
                SIMD3(-0.5, -0.5, 0.5),
                SIMD3(0.5, -0.5, 0.5),
                SIMD3(0.5, 0.5, 0.5),
                SIMD3(-0.5, 0.5, 0.5),
            ],
            [
                SIMD3(0.5, -0.5, -0.5),
                SIMD3(-0.5, -0.5, -0.5),
                SIMD3(-0.5, 0.5, -0.5),
                SIMD3(0.5, 0.5, -0.5),
            ],
            [
                SIMD3(-0.5, 0.5, 0.5),
                SIMD3(0.5, 0.5, 0.5),
                SIMD3(0.5, 0.5, -0.5),
                SIMD3(-0.5, 0.5, -0.5),
            ],
            [
                SIMD3(-0.5, -0.5, -0.5),
                SIMD3(0.5, -0.5, -0.5),
                SIMD3(0.5, -0.5, 0.5),
                SIMD3(-0.5, -0.5, 0.5),
            ],
            [
                SIMD3(0.5, -0.5, 0.5),
                SIMD3(0.5, -0.5, -0.5),
                SIMD3(0.5, 0.5, -0.5),
                SIMD3(0.5, 0.5, 0.5),
            ],
            [
                SIMD3(-0.5, -0.5, -0.5),
                SIMD3(-0.5, -0.5, 0.5),
                SIMD3(-0.5, 0.5, 0.5),
                SIMD3(-0.5, 0.5, -0.5),
            ],
        ]

        let normals: [SIMD3<Float>] = [
            SIMD3(0, 0, 1),
            SIMD3(0, 0, -1),
            SIMD3(0, 1, 0),
            SIMD3(0, -1, 0),
            SIMD3(1, 0, 0),
            SIMD3(-1, 0, 0),
        ]

        let quad = faces[faceIndex]
        let normal = normals[faceIndex]

        let v0 = offset + quad[0]
        let v1 = offset + quad[1]
        let v2 = offset + quad[2]
        let v3 = offset + quad[3]

        meshVertices.append(Vertex(position: v0, normal: normal, color: color))
        meshVertices.append(Vertex(position: v1, normal: normal, color: color))
        meshVertices.append(Vertex(position: v2, normal: normal, color: color))
        meshVertices.append(Vertex(position: v0, normal: normal, color: color))
        meshVertices.append(Vertex(position: v2, normal: normal, color: color))
        meshVertices.append(Vertex(position: v3, normal: normal, color: color))
    }
}
