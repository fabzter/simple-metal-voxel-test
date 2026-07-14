import Testing

@testable import VoxelEngine

struct VoxelWorldTests {
    @Test
    func outsideBoundsRulesStayStable() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)

        #expect(world.isSolid(x: 0, y: -1, z: 0))
        #expect(!world.isSolid(x: -1, y: 0, z: 0))
        #expect(!world.isSolid(x: 8, y: 0, z: 0))
        #expect(!world.isSolid(x: 0, y: 8, z: 0))
        #expect(!world.isSolid(x: 0, y: 0, z: 8))
    }

    @Test
    func sameSeedProducesSameTerrain() {
        let config = VoxelWorldConfiguration(seed: 1234)
        let worldA = VoxelWorld(gridSize: 16, generation: .terrain(config))
        let worldB = VoxelWorld(gridSize: 16, generation: .terrain(config))

        #expect(worldA.solidGrid == worldB.solidGrid)
    }

    @Test
    func differentSeedsProduceDifferentTerrain() {
        let worldA = VoxelWorld(gridSize: 16, generation: .terrain(.init(seed: 1)))
        let worldB = VoxelWorld(gridSize: 16, generation: .terrain(.init(seed: 2)))

        #expect(worldA.solidGrid != worldB.solidGrid)
    }

    @Test
    func generatedTerrainIncludesSubsurfaceCaves() {
        let world = VoxelWorld(gridSize: 48, generation: .terrain(.init(seed: 1234)))
        var foundCave = false

        for x in 0..<world.gridSize where !foundCave {
            for z in 0..<world.gridSize where !foundCave {
                guard
                    let topY = world.topSolidY(
                        inColumnX: x,
                        z: z,
                        withinYRange: 0...(world.gridSize - 1)),
                    topY >= 8
                else {
                    continue
                }

                for y in 3..<(topY - 2) where !world.isSolid(x: x, y: y, z: z) {
                    foundCave = true
                    break
                }
            }
        }

        #expect(foundCave)
    }

    @Test
    func generatedTerrainContainsWalkablePlainStretch() {
        let world = VoxelWorld(gridSize: 64, generation: .terrain(.init(seed: 4321)))
        let requiredRunLength = 10
        var foundStretch = false

        for z in 0..<world.gridSize where !foundStretch {
            var currentRun = 0
            var previousHeight: Int?

            for x in 0..<world.gridSize {
                guard
                    let height = world.topSolidY(
                        inColumnX: x,
                        z: z,
                        withinYRange: 0...(world.gridSize - 1))
                else {
                    currentRun = 0
                    previousHeight = nil
                    continue
                }

                if let previousHeight, abs(height - previousHeight) <= 1 {
                    currentRun += 1
                } else {
                    currentRun = 1
                }

                previousHeight = height
                if currentRun >= requiredRunLength {
                    foundStretch = true
                    break
                }
            }
        }

        #expect(foundStretch)
    }

    @Test
    func generatedTerrainIncludesNearSurfaceCaveOpenings() {
        let world = VoxelWorld(gridSize: 64, generation: .terrain(.init(seed: 2468)))
        var foundOpening = false

        for x in 1..<(world.gridSize - 1) where !foundOpening {
            for z in 1..<(world.gridSize - 1) where !foundOpening {
                guard
                    let topY = world.topSolidY(
                        inColumnX: x,
                        z: z,
                        withinYRange: 0...(world.gridSize - 1)),
                    topY >= 8
                else {
                    continue
                }

                let searchUpperY = max(3, topY - 1)
                let searchLowerY = max(3, topY - 5)
                for y in stride(from: searchUpperY, through: searchLowerY, by: -1) {
                    guard !world.isSolid(x: x, y: y, z: z) else {
                        continue
                    }

                    let hasSolidRoof = world.isSolid(x: x, y: y + 1, z: z)
                    let hasSideConnection =
                        !world.isSolid(x: x + 1, y: y, z: z)
                        || !world.isSolid(x: x - 1, y: y, z: z)
                        || !world.isSolid(x: x, y: y, z: z + 1)
                        || !world.isSolid(x: x, y: y, z: z - 1)
                    if hasSolidRoof && hasSideConnection {
                        foundOpening = true
                        break
                    }
                }
            }
        }

        #expect(foundOpening)
    }

    @Test
    func generatedTerrainStartsWithCleanMeshRevision() {
        let world = VoxelWorld(gridSize: 16, generation: .terrain(.default))
        #expect(world.meshRevision == 0)
    }

    @Test
    func meshRevisionChangesOnlyForRealVoxelEdits() {
        let world = VoxelWorld(gridSize: 8, generation: .empty)

        #expect(world.meshRevision == 0)

        world.setSolid(true, x: 1, y: 1, z: 1)
        #expect(world.meshRevision == 1)

        world.setSolid(true, x: 1, y: 1, z: 1)
        #expect(world.meshRevision == 1)

        world.setSolid(false, x: 1, y: 1, z: 1)
        #expect(world.meshRevision == 2)
    }

    @Test
    func chunkOccupancyTracksSetSolid() {
        let world = VoxelWorld(gridSize: 32, chunkSize: 16, generation: .empty)
        let originChunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let neighborChunk = VoxelChunkIndex(x: 1, y: 0, z: 0)

        #expect(!world.chunkHasSolidVoxels(originChunk))
        #expect(!world.chunkHasSolidVoxels(neighborChunk))

        world.setSolid(true, x: 2, y: 3, z: 4)
        #expect(world.chunkHasSolidVoxels(originChunk))
        #expect(!world.chunkHasSolidVoxels(neighborChunk))

        world.setSolid(true, x: 2, y: 3, z: 4)
        world.setSolid(false, x: 2, y: 3, z: 4)
        #expect(!world.chunkHasSolidVoxels(originChunk))
    }

    @Test
    func restoredWorldRebuildsChunkOccupancy() {
        let world = VoxelWorld(gridSize: 32, chunkSize: 16, generation: .empty)
        world.setSolid(true, x: 2, y: 2, z: 2)
        world.setSolid(true, x: 17, y: 2, z: 2)

        let snapshot = world.makeSaveSnapshot()
        let restored = VoxelWorld.restored(
            gridSize: 32, chunkSize: 16,
            seed: 1, words: snapshot.words, materials: snapshot.materials)

        #expect(restored != nil)
        let restoredWorld = restored!
        #expect(restoredWorld.chunkHasSolidVoxels(VoxelChunkIndex(x: 0, y: 0, z: 0)))
        #expect(restoredWorld.chunkHasSolidVoxels(VoxelChunkIndex(x: 1, y: 0, z: 0)))
        #expect(!restoredWorld.chunkHasSolidVoxels(VoxelChunkIndex(x: 0, y: 1, z: 0)))
    }

    @Test
    func chunkBoundaryEditInvalidatesAdjacentChunks() {
        let world = VoxelWorld(gridSize: 32, chunkSize: 16, generation: .empty)
        let leftChunk = VoxelChunkIndex(x: 0, y: 0, z: 0)
        let rightChunk = VoxelChunkIndex(x: 1, y: 0, z: 0)

        world.setSolid(true, x: 15, y: 4, z: 4)

        #expect(world.chunkRevision(for: leftChunk) == 1)
        #expect(world.chunkRevision(for: rightChunk) == 1)
    }

    @Test
    func placedBlocksKeepExplicitMaterialType() {
        let world = VoxelWorld(gridSize: 32, generation: .empty)
        world.setSolid(true, x: 4, y: 20, z: 4, material: .stone)

        #expect(world.materialType(x: 4, y: 20, z: 4) == .stone)
    }
}
