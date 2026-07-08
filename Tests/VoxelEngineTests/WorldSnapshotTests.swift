import Testing
import VoxelEngine

struct WorldSnapshotTests {

    @Test
    func snapshotRoundTripPreservesEdits() {
        let world = VoxelWorld(gridSize: 32, chunkSize: 8, generation: .empty)

        // Place a few blocks with explicit materials.
        world.setSolid(true, x: 5, y: 3, z: 5)
        world.setSolid(true, x: 7, y: 3, z: 5, material: .stone)
        world.setSolid(true, x: 10, y: 2, z: 15, material: .moss)

        let snapshot = world.makeSaveSnapshot()
        let restored = VoxelWorld.restored(
            gridSize: 32, chunkSize: 8,
            seed: 777, words: snapshot.words, materials: snapshot.materials)

        #expect(restored != nil)
        let r = restored!

        // Check solids.
        #expect(r.isSolid(x: 5, y: 3, z: 5) == true)
        #expect(r.isSolid(x: 7, y: 3, z: 5) == true)
        #expect(r.isSolid(x: 10, y: 2, z: 15) == true)
        // An untouched cell stays empty.
        #expect(r.isSolid(x: 0, y: 0, z: 0) == false)

        // Check materials.
        #expect(r.materialType(x: 7, y: 3, z: 5) == .stone)
        #expect(r.materialType(x: 10, y: 2, z: 15) == .moss)

        // Seed provenance survives restore (drives HUD seed display, re-save, Reset).
        #expect(r.generation == .terrain(VoxelWorldConfiguration(seed: 777)))
    }
}
