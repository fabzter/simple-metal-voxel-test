import simd

// `VoxelMesher` translates the abstract voxel grid into triangle data for the GPU.
//
// Key idea for beginners:
// every solid voxel is a cube, but we do NOT draw all 6 faces for all cubes.
// If one solid cube touches another solid cube, the shared face is hidden inside the world,
// so we skip it. That is why the mesher checks the 6 neighbors before emitting triangles.
struct VoxelMesher {
    func makeWorldMesh(for world: VoxelWorld) -> WorldMesh {
        var meshVertices: [Vertex] = []

        for x in 0..<world.gridSize {
            for y in 0..<world.gridSize {
                for z in 0..<world.gridSize where world.isSolid(x: x, y: y, z: z) {
                    let position = SIMD3<Float>(Float(x), Float(y), Float(z))

                    if !world.isSolid(x: x, y: y + 1, z: z) {
                        appendFace(
                            to: &meshVertices, offset: position, faceIndex: 2,
                            material: material(for: y, faceIndex: 2))
                    }
                    if !world.isSolid(x: x, y: y - 1, z: z) {
                        appendFace(
                            to: &meshVertices, offset: position, faceIndex: 3,
                            material: material(for: y, faceIndex: 3))
                    }
                    if !world.isSolid(x: x, y: y, z: z + 1) {
                        appendFace(
                            to: &meshVertices, offset: position, faceIndex: 0,
                            material: material(for: y, faceIndex: 0))
                    }
                    if !world.isSolid(x: x, y: y, z: z - 1) {
                        appendFace(
                            to: &meshVertices, offset: position, faceIndex: 1,
                            material: material(for: y, faceIndex: 1))
                    }
                    if !world.isSolid(x: x + 1, y: y, z: z) {
                        appendFace(
                            to: &meshVertices, offset: position, faceIndex: 4,
                            material: material(for: y, faceIndex: 4))
                    }
                    if !world.isSolid(x: x - 1, y: y, z: z) {
                        appendFace(
                            to: &meshVertices, offset: position, faceIndex: 5,
                            material: material(for: y, faceIndex: 5))
                    }
                }
            }
        }

        return WorldMesh(vertices: meshVertices)
    }

    private func material(for y: Int, faceIndex: Int) -> FaceMaterial {
        let isTop = faceIndex == 2
        let isBottom = faceIndex == 3

        if isTop && y >= 22 {
            return .flat(color: SIMD3<Float>(0.92, 0.92, 0.98))
        }

        if isTop && y >= 14 {
            return .textured(tile: .grass, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        }

        if isBottom {
            return .flat(color: SIMD3<Float>(0.22, 0.20, 0.18))
        }

        if y >= 14 {
            return .textured(tile: .dirt, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        }

        if y >= 10 {
            return .textured(tile: .moss, tint: SIMD3<Float>(0.95, 0.95, 0.95))
        }

        return .flat(color: SIMD3<Float>(0.50, 0.50, 0.55))
    }

    private func appendFace(
        to meshVertices: inout [Vertex],
        offset: SIMD3<Float>,
        faceIndex: Int,
        material: FaceMaterial
    ) {
        // Each entry is one quad centered on the voxel origin.
        // The mesher later turns that quad into two triangles.
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

        // One outward normal per face for simple flat lighting.
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
        let uvQuad = material.uvQuad

        let v0 = offset + quad[0]
        let v1 = offset + quad[1]
        let v2 = offset + quad[2]
        let v3 = offset + quad[3]

        // Two triangles per quad.
        meshVertices.append(material.vertex(position: v0, normal: normal, uv: uvQuad[0]))
        meshVertices.append(material.vertex(position: v1, normal: normal, uv: uvQuad[1]))
        meshVertices.append(material.vertex(position: v2, normal: normal, uv: uvQuad[2]))
        meshVertices.append(material.vertex(position: v0, normal: normal, uv: uvQuad[0]))
        meshVertices.append(material.vertex(position: v2, normal: normal, uv: uvQuad[2]))
        meshVertices.append(material.vertex(position: v3, normal: normal, uv: uvQuad[3]))
    }
}

private enum FaceMaterial {
    case flat(color: SIMD3<Float>)
    case textured(tile: MaterialAtlas.Tile, tint: SIMD3<Float>)

    var uvQuad: [SIMD2<Float>] {
        switch self {
        case .flat:
            return Array(repeating: .zero, count: 4)
        case .textured(let tile, _):
            return MaterialAtlas.region(for: tile).quadUVs
        }
    }

    func vertex(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) -> Vertex {
        switch self {
        case .flat(let color):
            return Vertex(
                position: position,
                normal: normal,
                color: color,
                uv: uv,
                materialMode: MaterialMode.flatColor.rawValue)
        case .textured(_, let tint):
            return Vertex(
                position: position,
                normal: normal,
                color: tint,
                uv: uv,
                materialMode: MaterialMode.textured.rawValue)
        }
    }
}
