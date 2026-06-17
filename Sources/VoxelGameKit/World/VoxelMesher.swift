import simd

// `VoxelMesher` translates the abstract voxel grid into triangle data for the GPU.
//
// Key idea for beginners:
// every solid voxel is a cube, but we do NOT draw all 6 faces for all cubes.
// If one solid cube touches another solid cube, the shared face is hidden inside the world,
// so we skip it. That is why the mesher checks the 6 neighbors before emitting triangles.
struct VoxelMesher {
    func makeWorldMesh(for world: VoxelWorld) -> WorldMesh {
        WorldMesh(
            vertices: world.allChunkIndices().flatMap {
                makeWorldMesh(for: world, chunkIndex: $0, voxelStride: 1).vertices
            })
    }

    func makeWorldMesh(for world: VoxelWorld, chunkIndex: VoxelChunkIndex, voxelStride: Int)
        -> WorldMesh
    {
        var meshVertices: [Vertex] = []

        let xRange = chunkRange(chunkIndex.x, chunkSize: world.chunkSize, gridSize: world.gridSize)
        let yRange = chunkRange(chunkIndex.y, chunkSize: world.chunkSize, gridSize: world.gridSize)
        let zRange = chunkRange(chunkIndex.z, chunkSize: world.chunkSize, gridSize: world.gridSize)

        // First-pass seam mitigation for coarse LODs: extend the sampling range by one stride so
        // coarse chunks slightly overlap their neighbors instead of leaving obvious cracks.
        // This is intentionally conservative and easy to debug. We should consider proper
        // transition stitching later if the visual seams become a quality problem.
        let overlapMargin = voxelStride > 1 ? voxelStride : 0

        let sampleXRange = stride(
            from: max(0, xRange.lowerBound - overlapMargin),
            to: min(world.gridSize, xRange.upperBound + overlapMargin), by: voxelStride)
        let sampleYRange = stride(
            from: max(0, yRange.lowerBound - overlapMargin),
            to: min(world.gridSize, yRange.upperBound + overlapMargin), by: voxelStride)
        let sampleZRange = stride(
            from: max(0, zRange.lowerBound - overlapMargin),
            to: min(world.gridSize, zRange.upperBound + overlapMargin), by: voxelStride)

        for x in sampleXRange {
            for y in sampleYRange {
                for z in sampleZRange {
                    guard cellIsSolid(world: world, x: x, y: y, z: z, voxelStride: voxelStride)
                    else {
                        continue
                    }

                    let centerOffset = Float(voxelStride - 1) * 0.5
                    let position = SIMD3<Float>(
                        Float(x) + centerOffset, Float(y) + centerOffset, Float(z) + centerOffset)
                    let topY =
                        dominantTopY(world: world, x: x, y: y, z: z, voxelStride: voxelStride) ?? y

                    if !cellIsSolid(
                        world: world, x: x, y: y + voxelStride, z: z, voxelStride: voxelStride)
                    {
                        appendFace(
                            to: &meshVertices,
                            offset: position,
                            faceIndex: 2,
                            voxelSize: Float(voxelStride),
                            material: material(for: topY, faceIndex: 2))
                    }
                    if !cellIsSolid(
                        world: world, x: x, y: y - voxelStride, z: z, voxelStride: voxelStride)
                    {
                        appendFace(
                            to: &meshVertices,
                            offset: position,
                            faceIndex: 3,
                            voxelSize: Float(voxelStride),
                            material: material(for: topY, faceIndex: 3))
                    }
                    if !cellIsSolid(
                        world: world, x: x, y: y, z: z + voxelStride, voxelStride: voxelStride)
                    {
                        appendFace(
                            to: &meshVertices,
                            offset: position,
                            faceIndex: 0,
                            voxelSize: Float(voxelStride),
                            material: material(for: topY, faceIndex: 0))
                    }
                    if !cellIsSolid(
                        world: world, x: x, y: y, z: z - voxelStride, voxelStride: voxelStride)
                    {
                        appendFace(
                            to: &meshVertices,
                            offset: position,
                            faceIndex: 1,
                            voxelSize: Float(voxelStride),
                            material: material(for: topY, faceIndex: 1))
                    }
                    if !cellIsSolid(
                        world: world, x: x + voxelStride, y: y, z: z, voxelStride: voxelStride)
                    {
                        appendFace(
                            to: &meshVertices,
                            offset: position,
                            faceIndex: 4,
                            voxelSize: Float(voxelStride),
                            material: material(for: topY, faceIndex: 4))
                    }
                    if !cellIsSolid(
                        world: world, x: x - voxelStride, y: y, z: z, voxelStride: voxelStride)
                    {
                        appendFace(
                            to: &meshVertices,
                            offset: position,
                            faceIndex: 5,
                            voxelSize: Float(voxelStride),
                            material: material(for: topY, faceIndex: 5))
                    }
                }
            }
        }

        return WorldMesh(vertices: meshVertices)
    }

    private func chunkRange(_ chunkComponent: Int, chunkSize: Int, gridSize: Int) -> Range<Int> {
        let start = chunkComponent * chunkSize
        let end = min(start + chunkSize, gridSize)
        return start..<end
    }

    private func cellIsSolid(world: VoxelWorld, x: Int, y: Int, z: Int, voxelStride: Int) -> Bool {
        if y < 0 { return true }
        if x < 0 || x >= world.gridSize || y >= world.gridSize || z < 0 || z >= world.gridSize {
            return false
        }

        let maxX = min(world.gridSize - 1, x + voxelStride - 1)
        let maxY = min(world.gridSize - 1, y + voxelStride - 1)
        let maxZ = min(world.gridSize - 1, z + voxelStride - 1)

        for sampleX in x...maxX {
            for sampleY in y...maxY {
                for sampleZ in z...maxZ where world.isSolid(x: sampleX, y: sampleY, z: sampleZ) {
                    return true
                }
            }
        }
        return false
    }

    private func dominantTopY(world: VoxelWorld, x: Int, y: Int, z: Int, voxelStride: Int) -> Int? {
        let maxX = min(world.gridSize - 1, x + voxelStride - 1)
        let maxZ = min(world.gridSize - 1, z + voxelStride - 1)
        let yRange = y...min(world.gridSize - 1, y + voxelStride - 1)

        var highest: Int?
        for sampleX in x...maxX {
            for sampleZ in z...maxZ {
                if let topY = world.topSolidY(inColumnX: sampleX, z: sampleZ, withinYRange: yRange)
                {
                    highest = max(highest ?? topY, topY)
                }
            }
        }
        return highest
    }

    private func material(for y: Int, faceIndex: Int) -> FaceMaterial {
        let isTop = faceIndex == 2
        let isBottom = faceIndex == 3

        if isTop && y >= 22 {
            return .flat(color: SIMD3<Float>(0.92, 0.92, 0.98), previewTile: .stone)
        }

        if isTop && y >= 14 {
            return .textured(tile: .grass, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        }

        if isBottom {
            return .flat(color: SIMD3<Float>(0.22, 0.20, 0.18), previewTile: .dirt)
        }

        if y >= 14 {
            return .textured(tile: .dirt, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        }

        if y >= 10 {
            return .textured(tile: .moss, tint: SIMD3<Float>(0.95, 0.95, 0.95))
        }

        return .flat(color: SIMD3<Float>(0.50, 0.50, 0.55), previewTile: .stone)
    }

    private func appendFace(
        to meshVertices: inout [Vertex],
        offset: SIMD3<Float>,
        faceIndex: Int,
        voxelSize: Float,
        material: FaceMaterial
    ) {
        let halfSize = voxelSize * 0.5
        let faces: [[SIMD3<Float>]] = [
            [
                SIMD3(-halfSize, -halfSize, halfSize),
                SIMD3(halfSize, -halfSize, halfSize),
                SIMD3(halfSize, halfSize, halfSize),
                SIMD3(-halfSize, halfSize, halfSize),
            ],
            [
                SIMD3(halfSize, -halfSize, -halfSize),
                SIMD3(-halfSize, -halfSize, -halfSize),
                SIMD3(-halfSize, halfSize, -halfSize),
                SIMD3(halfSize, halfSize, -halfSize),
            ],
            [
                SIMD3(-halfSize, halfSize, halfSize),
                SIMD3(halfSize, halfSize, halfSize),
                SIMD3(halfSize, halfSize, -halfSize),
                SIMD3(-halfSize, halfSize, -halfSize),
            ],
            [
                SIMD3(-halfSize, -halfSize, -halfSize),
                SIMD3(halfSize, -halfSize, -halfSize),
                SIMD3(halfSize, -halfSize, halfSize),
                SIMD3(-halfSize, -halfSize, halfSize),
            ],
            [
                SIMD3(halfSize, -halfSize, halfSize),
                SIMD3(halfSize, -halfSize, -halfSize),
                SIMD3(halfSize, halfSize, -halfSize),
                SIMD3(halfSize, halfSize, halfSize),
            ],
            [
                SIMD3(-halfSize, -halfSize, -halfSize),
                SIMD3(-halfSize, -halfSize, halfSize),
                SIMD3(-halfSize, halfSize, halfSize),
                SIMD3(-halfSize, halfSize, -halfSize),
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
        let uvQuad = material.uvQuad

        let v0 = offset + quad[0]
        let v1 = offset + quad[1]
        let v2 = offset + quad[2]
        let v3 = offset + quad[3]

        meshVertices.append(material.vertex(position: v0, normal: normal, uv: uvQuad[0]))
        meshVertices.append(material.vertex(position: v1, normal: normal, uv: uvQuad[1]))
        meshVertices.append(material.vertex(position: v2, normal: normal, uv: uvQuad[2]))
        meshVertices.append(material.vertex(position: v0, normal: normal, uv: uvQuad[0]))
        meshVertices.append(material.vertex(position: v2, normal: normal, uv: uvQuad[2]))
        meshVertices.append(material.vertex(position: v3, normal: normal, uv: uvQuad[3]))
    }
}

private enum FaceMaterial {
    case flat(color: SIMD3<Float>, previewTile: MaterialAtlas.Tile)
    case textured(tile: MaterialAtlas.Tile, tint: SIMD3<Float>)

    var uvQuad: [SIMD2<Float>] {
        switch self {
        case .flat(_, let previewTile):
            return MaterialAtlas.region(for: previewTile).quadUVs
        case .textured(let tile, _):
            return MaterialAtlas.region(for: tile).quadUVs
        }
    }

    func vertex(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) -> Vertex {
        switch self {
        case .flat(let color, _):
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
