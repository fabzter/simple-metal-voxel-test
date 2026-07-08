import simd

struct VoxelMesher {
    private let seamOverlapEpsilon: Float = 0.02

    func makeWorldMesh(for world: VoxelWorld) -> WorldMesh {
        WorldMesh(
            vertices: world.allChunkIndices().flatMap {
                makeWorldMesh(for: world, chunkIndex: $0, voxelStride: 1).vertices
            })
    }

    private struct ChunkBoundaryTouches {
        let positiveX: Bool
        let negativeX: Bool
        let positiveY: Bool
        let negativeY: Bool
        let positiveZ: Bool
        let negativeZ: Bool
    }

    private struct VerticalBounds {
        let minY: Int
        let maxY: Int
    }

    private struct FaceAxes {
        let uComponent: WritableKeyPath<SIMD3<Float>, Float>
        let uAscending: Bool
        let vComponent: WritableKeyPath<SIMD3<Float>, Float>
        let vAscending: Bool
    }

    func makeWorldMesh(
        for world: VoxelWorld,
        chunkIndex: VoxelChunkIndex,
        voxelStride: Int,
        seamConfiguration: ChunkSeamConfiguration = .none
    )
        -> WorldMesh
    {
        var meshVertices: [Vertex] = []

        let xRange = chunkRange(chunkIndex.x, chunkSize: world.chunkSize, gridSize: world.gridSize)
        let yRange = chunkRange(chunkIndex.y, chunkSize: world.chunkSize, gridSize: world.gridSize)
        let zRange = chunkRange(chunkIndex.z, chunkSize: world.chunkSize, gridSize: world.gridSize)

        let sampleXRange = stride(from: xRange.lowerBound, to: xRange.upperBound, by: voxelStride)
        let sampleYRange = stride(from: yRange.lowerBound, to: yRange.upperBound, by: voxelStride)
        let sampleZRange = stride(from: zRange.lowerBound, to: zRange.upperBound, by: voxelStride)

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
                    let verticalBounds =
                        verticalBounds(
                            world: world,
                            x: x,
                            y: y,
                            z: z,
                            voxelStride: voxelStride) ?? VerticalBounds(minY: y, maxY: y)
                    let topY = verticalBounds.maxY
                    let blockType = world.materialType(x: x, y: topY, z: z) ?? .stone
                    let boundaryTouches = ChunkBoundaryTouches(
                        positiveX: x + voxelStride >= xRange.upperBound,
                        negativeX: x == xRange.lowerBound,
                        positiveY: y + voxelStride >= yRange.upperBound,
                        negativeY: y == yRange.lowerBound,
                        positiveZ: z + voxelStride >= zRange.upperBound,
                        negativeZ: z == zRange.lowerBound)

                    emitFace(
                        to: &meshVertices,
                        world: world,
                        cellX: x,
                        cellY: y,
                        cellZ: z,
                        neighborX: x,
                        neighborY: y + voxelStride,
                        neighborZ: z,
                        offset: position,
                        verticalBounds: verticalBounds,
                        faceIndex: 2,
                        voxelStride: voxelStride,
                        boundaryTouches: boundaryTouches,
                        seamConfiguration: seamConfiguration,
                        material: material(for: blockType, topY: topY, faceIndex: 2))
                    emitFace(
                        to: &meshVertices,
                        world: world,
                        cellX: x,
                        cellY: y,
                        cellZ: z,
                        neighborX: x,
                        neighborY: y - voxelStride,
                        neighborZ: z,
                        offset: position,
                        verticalBounds: verticalBounds,
                        faceIndex: 3,
                        voxelStride: voxelStride,
                        boundaryTouches: boundaryTouches,
                        seamConfiguration: seamConfiguration,
                        material: material(for: blockType, topY: topY, faceIndex: 3))
                    emitFace(
                        to: &meshVertices,
                        world: world,
                        cellX: x,
                        cellY: y,
                        cellZ: z,
                        neighborX: x,
                        neighborY: y,
                        neighborZ: z + voxelStride,
                        offset: position,
                        verticalBounds: verticalBounds,
                        faceIndex: 0,
                        voxelStride: voxelStride,
                        boundaryTouches: boundaryTouches,
                        seamConfiguration: seamConfiguration,
                        material: material(for: blockType, topY: topY, faceIndex: 0))
                    emitFace(
                        to: &meshVertices,
                        world: world,
                        cellX: x,
                        cellY: y,
                        cellZ: z,
                        neighborX: x,
                        neighborY: y,
                        neighborZ: z - voxelStride,
                        offset: position,
                        verticalBounds: verticalBounds,
                        faceIndex: 1,
                        voxelStride: voxelStride,
                        boundaryTouches: boundaryTouches,
                        seamConfiguration: seamConfiguration,
                        material: material(for: blockType, topY: topY, faceIndex: 1))
                    emitFace(
                        to: &meshVertices,
                        world: world,
                        cellX: x,
                        cellY: y,
                        cellZ: z,
                        neighborX: x + voxelStride,
                        neighborY: y,
                        neighborZ: z,
                        offset: position,
                        verticalBounds: verticalBounds,
                        faceIndex: 4,
                        voxelStride: voxelStride,
                        boundaryTouches: boundaryTouches,
                        seamConfiguration: seamConfiguration,
                        material: material(for: blockType, topY: topY, faceIndex: 4))
                    emitFace(
                        to: &meshVertices,
                        world: world,
                        cellX: x,
                        cellY: y,
                        cellZ: z,
                        neighborX: x - voxelStride,
                        neighborY: y,
                        neighborZ: z,
                        offset: position,
                        verticalBounds: verticalBounds,
                        faceIndex: 5,
                        voxelStride: voxelStride,
                        boundaryTouches: boundaryTouches,
                        seamConfiguration: seamConfiguration,
                        material: material(for: blockType, topY: topY, faceIndex: 5))
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

    private func verticalBounds(
        world: VoxelWorld,
        x: Int,
        y: Int,
        z: Int,
        voxelStride: Int
    ) -> VerticalBounds? {
        let maxX = min(world.gridSize - 1, x + voxelStride - 1)
        let maxY = min(world.gridSize - 1, y + voxelStride - 1)
        let maxZ = min(world.gridSize - 1, z + voxelStride - 1)

        var lowest: Int?
        var highest: Int?
        for sampleX in x...maxX {
            for sampleY in y...maxY {
                for sampleZ in z...maxZ where world.isSolid(x: sampleX, y: sampleY, z: sampleZ) {
                    lowest = min(lowest ?? sampleY, sampleY)
                    highest = max(highest ?? sampleY, sampleY)
                }
            }
        }

        guard let lowest, let highest else {
            return nil
        }

        return VerticalBounds(minY: lowest, maxY: highest)
    }

    private func material(for blockType: BlockMaterialType, topY: Int, faceIndex: Int)
        -> FaceMaterial
    {
        let isTop = faceIndex == 2
        let isBottom = faceIndex == 3

        if isBottom {
            return .flat(color: SIMD3<Float>(0.22, 0.20, 0.18), previewTile: .dirt)
        }

        switch blockType {
        case .grass:
            return isTop
                ? .textured(tile: .grass, tint: SIMD3<Float>(1.0, 1.0, 1.0))
                : .textured(tile: .dirt, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        case .dirt:
            return .textured(tile: .dirt, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        case .stone:
            return .flat(color: SIMD3<Float>(0.50, 0.50, 0.55), previewTile: .stone)
        case .moss:
            return .textured(tile: .moss, tint: SIMD3<Float>(0.95, 0.95, 0.95))
        case .snow:
            if isTop && topY >= 22 {
                return .flat(color: SIMD3<Float>(0.92, 0.92, 0.98), previewTile: .stone)
            }
            return .flat(color: SIMD3<Float>(0.85, 0.86, 0.90), previewTile: .stone)
        }
    }

    private func appendFace(
        to meshVertices: inout [Vertex],
        offset: SIMD3<Float>,
        verticalBounds: VerticalBounds,
        faceIndex: Int,
        voxelSize: Float,
        material: FaceMaterial,
        edgeSubdivisionCounts: [Int] = [1, 1, 1, 1],
        edgeOverlapFlags: [Bool] = [false, false, false, false]
    ) {
        var worldQuad = faceQuad(
            offset: offset,
            verticalBounds: verticalBounds,
            faceIndex: faceIndex,
            voxelSize: voxelSize)
        if faceIndex == 2 {
            applyTopFaceOverlap(to: &worldQuad, edgeOverlapFlags: edgeOverlapFlags)
        }
        let uvQuad = material.uvQuad
        let uSegments = max(1, max(edgeSubdivisionCounts[0], edgeSubdivisionCounts[2]))
        let vSegments = max(1, max(edgeSubdivisionCounts[1], edgeSubdivisionCounts[3]))

        for vIndex in 0..<vSegments {
            let v0 = Float(vIndex) / Float(vSegments)
            let v1 = Float(vIndex + 1) / Float(vSegments)

            for uIndex in 0..<uSegments {
                let u0 = Float(uIndex) / Float(uSegments)
                let u1 = Float(uIndex + 1) / Float(uSegments)

                let quad = [
                    bilinearPoint(quad: worldQuad, u: u0, v: v0),
                    bilinearPoint(quad: worldQuad, u: u1, v: v0),
                    bilinearPoint(quad: worldQuad, u: u1, v: v1),
                    bilinearPoint(quad: worldQuad, u: u0, v: v1),
                ]
                let quadUV = [
                    bilinearUV(quad: uvQuad, u: u0, v: v0),
                    bilinearUV(quad: uvQuad, u: u1, v: v0),
                    bilinearUV(quad: uvQuad, u: u1, v: v1),
                    bilinearUV(quad: uvQuad, u: u0, v: v1),
                ]

                appendQuad(
                    to: &meshVertices,
                    quad: quad,
                    uvQuad: quadUV,
                    normal: faceNormal(faceIndex),
                    material: material)
            }
        }
    }

    private func emitFace(
        to meshVertices: inout [Vertex],
        world: VoxelWorld,
        cellX: Int,
        cellY: Int,
        cellZ: Int,
        neighborX: Int,
        neighborY: Int,
        neighborZ: Int,
        offset: SIMD3<Float>,
        verticalBounds: VerticalBounds,
        faceIndex: Int,
        voxelStride: Int,
        boundaryTouches: ChunkBoundaryTouches,
        seamConfiguration: ChunkSeamConfiguration,
        material: FaceMaterial
    ) {
        if let finerStride = finerBoundaryStride(
            faceIndex: faceIndex,
            voxelStride: voxelStride,
            boundaryTouches: boundaryTouches,
            seamConfiguration: seamConfiguration)
        {
            appendTransitionBoundaryFace(
                to: &meshVertices,
                world: world,
                cellX: cellX,
                cellY: cellY,
                cellZ: cellZ,
                offset: offset,
                verticalBounds: verticalBounds,
                faceIndex: faceIndex,
                voxelStride: voxelStride,
                finerStride: finerStride,
                material: material)
            return
        }

        let neighborIsSolid = cellIsSolid(
            world: world,
            x: neighborX,
            y: neighborY,
            z: neighborZ,
            voxelStride: voxelStride)
        // For coarse LOD cells on the terrain surface, don't cull faces even if the
        // neighbor cell is solid. The camera can see the cell interior from below/above
        // and needs the entry/exit faces for a watertight surface. This prevents the
        // "invisible solid interior" problem with coarse LOD cells.
        let isTerrainSurface: Bool = {
            guard voxelStride > 1 else { return false }
            guard faceIndex != 3 else { return false }
            let cellAboveY = cellY + voxelStride
            return !cellIsSolid(
                world: world, x: cellX, y: cellAboveY, z: cellZ, voxelStride: voxelStride)
        }()
        guard !neighborIsSolid || isTerrainSurface else {
            return
        }

        appendFace(
            to: &meshVertices,
            offset: offset,
            verticalBounds: verticalBounds,
            faceIndex: faceIndex,
            voxelSize: Float(voxelStride),
            material: material,
            edgeSubdivisionCounts: stitchedEdgeSubdivisionCounts(
                faceIndex: faceIndex,
                voxelStride: voxelStride,
                boundaryTouches: boundaryTouches,
                seamConfiguration: seamConfiguration),
            edgeOverlapFlags: topFaceEdgeOverlapFlags(
                faceIndex: faceIndex,
                seamConfiguration: seamConfiguration))
    }

    private func finerBoundaryStride(
        faceIndex: Int,
        voxelStride: Int,
        boundaryTouches: ChunkBoundaryTouches,
        seamConfiguration: ChunkSeamConfiguration
    ) -> Int? {
        let direction: ChunkBoundaryDirection
        let touchesBoundary: Bool

        switch faceIndex {
        case 0:
            direction = .positiveZ
            touchesBoundary = boundaryTouches.positiveZ
        case 1:
            direction = .negativeZ
            touchesBoundary = boundaryTouches.negativeZ
        case 2:
            direction = .positiveY
            touchesBoundary = boundaryTouches.positiveY
        case 3:
            direction = .negativeY
            touchesBoundary = boundaryTouches.negativeY
        case 4:
            direction = .positiveX
            touchesBoundary = boundaryTouches.positiveX
        case 5:
            direction = .negativeX
            touchesBoundary = boundaryTouches.negativeX
        default:
            return nil
        }

        guard
            touchesBoundary,
            let finerStride = seamConfiguration.finerStride(for: direction),
            finerStride > 0,
            finerStride < voxelStride,
            voxelStride.isMultiple(of: finerStride)
        else {
            return nil
        }

        return finerStride
    }

    private func appendTransitionBoundaryFace(
        to meshVertices: inout [Vertex],
        world: VoxelWorld,
        cellX: Int,
        cellY: Int,
        cellZ: Int,
        offset: SIMD3<Float>,
        verticalBounds: VerticalBounds,
        faceIndex: Int,
        voxelStride: Int,
        finerStride: Int,
        material: FaceMaterial
    ) {
        let fullQuad = faceQuad(
            offset: offset,
            verticalBounds: verticalBounds,
            faceIndex: faceIndex,
            voxelSize: Float(voxelStride))
        let uvQuad = material.uvQuad
        let subfaceCount = voxelStride / finerStride

        for vIndex in 0..<subfaceCount {
            for uIndex in 0..<subfaceCount {
                let localU = uIndex * finerStride
                let localV = vIndex * finerStride
                _ = transitionSubQuadEmitsTopSkirt(
                    cellY: cellY,
                    verticalBounds: verticalBounds,
                    voxelStride: voxelStride,
                    finerStride: finerStride,
                    localV: localV)
                // The coarse cell is already known to be solid (we're inside the meshing loop
                // for solid cells). Always emit every boundary subface to keep the seam
                // watertight. Culling subfaces based on neighbor occupancy created holes where
                // both the fine side and coarse side assumed the other would provide the face.

                let u0 = normalizedCoordinate(
                    localOffset: localU,
                    segmentSize: finerStride,
                    totalSize: voxelStride,
                    ascending: true,
                    upperBound: false)
                let u1 = normalizedCoordinate(
                    localOffset: localU,
                    segmentSize: finerStride,
                    totalSize: voxelStride,
                    ascending: true,
                    upperBound: true)
                let v0 = normalizedCoordinate(
                    localOffset: localV,
                    segmentSize: finerStride,
                    totalSize: voxelStride,
                    ascending: true,
                    upperBound: false)
                let v1 = normalizedCoordinate(
                    localOffset: localV,
                    segmentSize: finerStride,
                    totalSize: voxelStride,
                    ascending: true,
                    upperBound: true)
                let overlap = seamOverlapEpsilon / Float(voxelStride)
                let expandedU0 = max(0, u0 - overlap)
                let expandedU1 = min(1, u1 + overlap)
                let expandedV0 = max(0, v0 - overlap)
                let expandedV1 = min(1, v1 + overlap)

                let subQuad =
                    transitionSideSubQuad(
                        cellX: cellX,
                        cellY: cellY,
                        cellZ: cellZ,
                        verticalBounds: verticalBounds,
                        faceIndex: faceIndex,
                        voxelStride: voxelStride,
                        finerStride: finerStride,
                        localU: localU,
                        localV: localV)
                    ?? [
                        bilinearPoint(quad: fullQuad, u: expandedU0, v: expandedV0),
                        bilinearPoint(quad: fullQuad, u: expandedU1, v: expandedV0),
                        bilinearPoint(quad: fullQuad, u: expandedU1, v: expandedV1),
                        bilinearPoint(quad: fullQuad, u: expandedU0, v: expandedV1),
                    ]
                let subUVQuad = [
                    bilinearUV(quad: uvQuad, u: expandedU0, v: expandedV0),
                    bilinearUV(quad: uvQuad, u: expandedU1, v: expandedV0),
                    bilinearUV(quad: uvQuad, u: expandedU1, v: expandedV1),
                    bilinearUV(quad: uvQuad, u: expandedU0, v: expandedV1),
                ]

                appendQuad(
                    to: &meshVertices,
                    quad: subQuad,
                    uvQuad: subUVQuad,
                    normal: faceNormal(faceIndex),
                    material: material,
                    doubleSided: true)
            }
        }
    }

    private func transitionSubQuadEmitsTopSkirt(
        cellY: Int,
        verticalBounds: VerticalBounds,
        voxelStride: Int,
        finerStride: Int,
        localV: Int
    ) -> Bool {
        let fullMaxY = Float(verticalBounds.maxY + 1) - 0.5
        let coarseCeilingY = Float(cellY + voxelStride) - 0.5
        let clippedSegmentMaxY = min(Float(cellY + localV + finerStride) - 0.5, fullMaxY)
        return abs(clippedSegmentMaxY - fullMaxY) < 0.001 && coarseCeilingY > fullMaxY + 0.001
    }

    private func transitionSideSubQuad(
        cellX: Int,
        cellY: Int,
        cellZ: Int,
        verticalBounds: VerticalBounds,
        faceIndex: Int,
        voxelStride: Int,
        finerStride: Int,
        localU: Int,
        localV: Int
    ) -> [SIMD3<Float>]? {
        let fullMinX = Float(cellX) - 0.5
        let fullMaxX = Float(cellX + voxelStride) - 0.5
        let fullMinZ = Float(cellZ) - 0.5
        let fullMaxZ = Float(cellZ + voxelStride) - 0.5
        let fullMinY = Float(verticalBounds.minY) - 0.5
        let fullMaxY = Float(verticalBounds.maxY + 1) - 0.5
        let coarseCeilingY = Float(cellY + voxelStride) - 0.5

        let segmentMinY = max(Float(cellY + localV) - 0.5, fullMinY)
        let clippedSegmentMaxY = min(Float(cellY + localV + finerStride) - 0.5, fullMaxY)
        let segmentMaxY =
            abs(clippedSegmentMaxY - fullMaxY) < 0.001
            ? max(clippedSegmentMaxY, coarseCeilingY)
            : clippedSegmentMaxY
        guard segmentMinY < segmentMaxY else {
            return nil
        }

        switch faceIndex {
        case 0:
            let minX = max(fullMinX, Float(cellX + localU) - 0.5 - seamOverlapEpsilon)
            let maxX = min(fullMaxX, Float(cellX + localU + finerStride) - 0.5 + seamOverlapEpsilon)
            let z = fullMaxZ
            return [
                SIMD3(minX, segmentMinY, z),
                SIMD3(maxX, segmentMinY, z),
                SIMD3(maxX, segmentMaxY, z),
                SIMD3(minX, segmentMaxY, z),
            ]
        case 1:
            let minX = max(fullMinX, Float(cellX + localU) - 0.5 - seamOverlapEpsilon)
            let maxX = min(fullMaxX, Float(cellX + localU + finerStride) - 0.5 + seamOverlapEpsilon)
            let z = fullMinZ
            return [
                SIMD3(maxX, segmentMinY, z),
                SIMD3(minX, segmentMinY, z),
                SIMD3(minX, segmentMaxY, z),
                SIMD3(maxX, segmentMaxY, z),
            ]
        case 4:
            let minZ = max(fullMinZ, Float(cellZ + localU) - 0.5 - seamOverlapEpsilon)
            let maxZ = min(fullMaxZ, Float(cellZ + localU + finerStride) - 0.5 + seamOverlapEpsilon)
            let x = fullMaxX
            return [
                SIMD3(x, segmentMinY, maxZ),
                SIMD3(x, segmentMinY, minZ),
                SIMD3(x, segmentMaxY, minZ),
                SIMD3(x, segmentMaxY, maxZ),
            ]
        case 5:
            let minZ = max(fullMinZ, Float(cellZ + localU) - 0.5 - seamOverlapEpsilon)
            let maxZ = min(fullMaxZ, Float(cellZ + localU + finerStride) - 0.5 + seamOverlapEpsilon)
            let x = fullMinX
            return [
                SIMD3(x, segmentMinY, minZ),
                SIMD3(x, segmentMinY, maxZ),
                SIMD3(x, segmentMaxY, maxZ),
                SIMD3(x, segmentMaxY, minZ),
            ]
        default:
            return nil
        }
    }

    private func normalizedCoordinate(
        localOffset: Int,
        segmentSize: Int,
        totalSize: Int,
        ascending: Bool,
        upperBound: Bool
    ) -> Float {
        let start = Float(localOffset) / Float(totalSize)
        let end = Float(localOffset + segmentSize) / Float(totalSize)
        if ascending {
            return upperBound ? end : start
        }
        return upperBound ? (1 - start) : (1 - end)
    }

    private func bilinearPoint(
        quad: [SIMD3<Float>],
        u: Float,
        v: Float
    ) -> SIMD3<Float> {
        let bottom = simd_mix(quad[0], quad[1], SIMD3<Float>(repeating: u))
        let top = simd_mix(quad[3], quad[2], SIMD3<Float>(repeating: u))
        return simd_mix(bottom, top, SIMD3<Float>(repeating: v))
    }

    private func bilinearUV(
        quad: [SIMD2<Float>],
        u: Float,
        v: Float
    ) -> SIMD2<Float> {
        let bottom = simd_mix(quad[0], quad[1], SIMD2<Float>(repeating: u))
        let top = simd_mix(quad[3], quad[2], SIMD2<Float>(repeating: u))
        return simd_mix(bottom, top, SIMD2<Float>(repeating: v))
    }

    private func appendQuad(
        to meshVertices: inout [Vertex],
        quad: [SIMD3<Float>],
        uvQuad: [SIMD2<Float>],
        normal: SIMD3<Float>,
        material: FaceMaterial,
        doubleSided: Bool = false
    ) {
        guard quad.count == 4, uvQuad.count == 4 else {
            return
        }

        meshVertices.append(material.vertex(position: quad[0], normal: normal, uv: uvQuad[0]))
        meshVertices.append(material.vertex(position: quad[1], normal: normal, uv: uvQuad[1]))
        meshVertices.append(material.vertex(position: quad[2], normal: normal, uv: uvQuad[2]))
        meshVertices.append(material.vertex(position: quad[0], normal: normal, uv: uvQuad[0]))
        meshVertices.append(material.vertex(position: quad[2], normal: normal, uv: uvQuad[2]))
        meshVertices.append(material.vertex(position: quad[3], normal: normal, uv: uvQuad[3]))

        guard doubleSided else {
            return
        }

        let reverseNormal = -normal
        meshVertices.append(
            material.vertex(position: quad[0], normal: reverseNormal, uv: uvQuad[0]))
        meshVertices.append(
            material.vertex(position: quad[3], normal: reverseNormal, uv: uvQuad[3]))
        meshVertices.append(
            material.vertex(position: quad[2], normal: reverseNormal, uv: uvQuad[2]))
        meshVertices.append(
            material.vertex(position: quad[0], normal: reverseNormal, uv: uvQuad[0]))
        meshVertices.append(
            material.vertex(position: quad[2], normal: reverseNormal, uv: uvQuad[2]))
        meshVertices.append(
            material.vertex(position: quad[1], normal: reverseNormal, uv: uvQuad[1]))
    }

    private func faceQuad(
        offset: SIMD3<Float>,
        verticalBounds: VerticalBounds,
        faceIndex: Int,
        voxelSize: Float
    ) -> [SIMD3<Float>] {
        let halfSize = voxelSize * 0.5
        let minY = Float(verticalBounds.minY) - 0.5
        let maxY = Float(verticalBounds.maxY) + 0.5
        let faces: [[SIMD3<Float>]] = [
            [
                SIMD3(-halfSize, minY - offset.y, halfSize),
                SIMD3(halfSize, minY - offset.y, halfSize),
                SIMD3(halfSize, maxY - offset.y, halfSize),
                SIMD3(-halfSize, maxY - offset.y, halfSize),
            ],
            [
                SIMD3(halfSize, minY - offset.y, -halfSize),
                SIMD3(-halfSize, minY - offset.y, -halfSize),
                SIMD3(-halfSize, maxY - offset.y, -halfSize),
                SIMD3(halfSize, maxY - offset.y, -halfSize),
            ],
            [
                SIMD3(-halfSize, maxY - offset.y, halfSize),
                SIMD3(halfSize, maxY - offset.y, halfSize),
                SIMD3(halfSize, maxY - offset.y, -halfSize),
                SIMD3(-halfSize, maxY - offset.y, -halfSize),
            ],
            [
                SIMD3(-halfSize, minY - offset.y, -halfSize),
                SIMD3(halfSize, minY - offset.y, -halfSize),
                SIMD3(halfSize, minY - offset.y, halfSize),
                SIMD3(-halfSize, minY - offset.y, halfSize),
            ],
            [
                SIMD3(halfSize, minY - offset.y, halfSize),
                SIMD3(halfSize, minY - offset.y, -halfSize),
                SIMD3(halfSize, maxY - offset.y, -halfSize),
                SIMD3(halfSize, maxY - offset.y, halfSize),
            ],
            [
                SIMD3(-halfSize, minY - offset.y, -halfSize),
                SIMD3(-halfSize, minY - offset.y, halfSize),
                SIMD3(-halfSize, maxY - offset.y, halfSize),
                SIMD3(-halfSize, maxY - offset.y, -halfSize),
            ],
        ]

        return faces[faceIndex].map { offset + $0 }
    }

    private func faceNormal(_ faceIndex: Int) -> SIMD3<Float> {
        [
            SIMD3(0, 0, 1),
            SIMD3(0, 0, -1),
            SIMD3(0, 1, 0),
            SIMD3(0, -1, 0),
            SIMD3(1, 0, 0),
            SIMD3(-1, 0, 0),
        ][faceIndex]
    }

    private func stitchedEdgeSubdivisionCounts(
        faceIndex: Int,
        voxelStride: Int,
        boundaryTouches: ChunkBoundaryTouches,
        seamConfiguration: ChunkSeamConfiguration
    ) -> [Int] {
        guard voxelStride > 1 else {
            return [1, 1, 1, 1]
        }

        let edgeDirections: [[ChunkBoundaryDirection]] = [
            [.negativeY, .positiveX, .positiveY, .negativeX],
            [.negativeY, .negativeX, .positiveY, .positiveX],
            [.positiveZ, .positiveX, .negativeZ, .negativeX],
            [.negativeZ, .positiveX, .positiveZ, .negativeX],
            [.negativeY, .negativeZ, .positiveY, .positiveZ],
            [.negativeY, .positiveZ, .positiveY, .negativeZ],
        ]

        var segments = [1, 1, 1, 1]
        for edgeIndex in 0..<4 {
            let direction = edgeDirections[faceIndex][edgeIndex]
            guard touches(direction: direction, boundaryTouches: boundaryTouches),
                let finerStride = seamConfiguration.finerStride(for: direction),
                finerStride > 0,
                finerStride < voxelStride,
                voxelStride.isMultiple(of: finerStride)
            else {
                continue
            }

            segments[edgeIndex] = voxelStride / finerStride
        }

        return segments
    }

    private func topFaceEdgeOverlapFlags(
        faceIndex: Int,
        seamConfiguration: ChunkSeamConfiguration
    ) -> [Bool] {
        guard faceIndex == 2 else {
            return [false, false, false, false]
        }

        return [
            seamConfiguration.positiveZFinerStride != nil,
            seamConfiguration.positiveXFinerStride != nil,
            seamConfiguration.negativeZFinerStride != nil,
            seamConfiguration.negativeXFinerStride != nil,
        ]
    }

    private func applyTopFaceOverlap(
        to quad: inout [SIMD3<Float>],
        edgeOverlapFlags: [Bool]
    ) {
        guard quad.count == 4 else {
            return
        }

        if edgeOverlapFlags[0] {  // +Z edge
            quad[0].z += seamOverlapEpsilon
            quad[1].z += seamOverlapEpsilon
        }
        if edgeOverlapFlags[1] {  // +X edge
            quad[1].x += seamOverlapEpsilon
            quad[2].x += seamOverlapEpsilon
        }
        if edgeOverlapFlags[2] {  // -Z edge
            quad[2].z -= seamOverlapEpsilon
            quad[3].z -= seamOverlapEpsilon
        }
        if edgeOverlapFlags[3] {  // -X edge
            quad[3].x -= seamOverlapEpsilon
            quad[0].x -= seamOverlapEpsilon
        }
    }

    private func touches(
        direction: ChunkBoundaryDirection,
        boundaryTouches: ChunkBoundaryTouches
    ) -> Bool {
        switch direction {
        case .positiveX:
            boundaryTouches.positiveX
        case .negativeX:
            boundaryTouches.negativeX
        case .positiveY:
            boundaryTouches.positiveY
        case .negativeY:
            boundaryTouches.negativeY
        case .positiveZ:
            boundaryTouches.positiveZ
        case .negativeZ:
            boundaryTouches.negativeZ
        }
    }
}
