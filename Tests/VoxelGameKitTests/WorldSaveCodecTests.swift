import Foundation
import Testing
import VoxelGameKit

/// Tests for the binary world-save codec and BitGrid restore init.
struct WorldSaveCodecTests {

    // MARK: - Round-trip

    @Test
    func roundTripPreservesAllState() {
        let state = WorldSaveState(
            gridSize: 5, chunkSize: 4, seed: 12345,
            playerPosition: SIMD3<Float>(3.5, 8.0, 12.25),
            cameraYaw: 1.2, cameraPitch: -0.7,
            isFlying: true,
            selectedMaterial: .stone,
            solidWords: [0xDEAD_BEEF_CAFE_BABE, 0x1234_5678_90AB_CDEF],
            materials: [10: .moss, 100: .snow])

        let data = WorldSaveCodec.encode(state)
        let restored = WorldSaveCodec.decode(data)

        #expect(restored != nil)
        #expect(restored == state)
    }

    // MARK: - Rejection cases

    @Test
    func truncatedDataReturnsNil() {
        let state = WorldSaveState(
            gridSize: 5, chunkSize: 4, seed: 0,
            playerPosition: .zero, cameraYaw: 0, cameraPitch: 0,
            isFlying: false, selectedMaterial: .grass,
            solidWords: [0, 0], materials: [:])
        let fullData = WorldSaveCodec.encode(state)
        // Truncate to half.
        let truncated = fullData.prefix(fullData.count / 2)
        #expect(WorldSaveCodec.decode(Data(truncated)) == nil)
    }

    @Test
    func badMagicReturnsNil() {
        var data = WorldSaveCodec.encode(
            WorldSaveState(
                gridSize: 8, chunkSize: 4, seed: 0,
                playerPosition: .zero, cameraYaw: 0, cameraPitch: 0,
                isFlying: false, selectedMaterial: .grass,
                solidWords: [], materials: [:]))
        // Corrupt magic.
        data[0] = 0xFF
        #expect(WorldSaveCodec.decode(data) == nil)
    }

    @Test
    func mismatchedWordCountReturnsNil() {
        let data = WorldSaveCodec.encode(
            WorldSaveState(
                gridSize: 5, chunkSize: 4, seed: 0,
                playerPosition: .zero, cameraYaw: 0, cameraPitch: 0,
                isFlying: false, selectedMaterial: .grass,
                solidWords: [UInt64](repeating: 0, count: 10),  // correct is 2 for gridSize 5
                materials: [:]))
        #expect(WorldSaveCodec.decode(data) == nil)
    }

    @Test
    func unknownMaterialReturnsNil() {
        // Manually create data with an invalid material code byte.
        let base = WorldSaveCodec.encode(
            WorldSaveState(
                gridSize: 8, chunkSize: 4, seed: 0,
                playerPosition: .zero, cameraYaw: 0, cameraPitch: 0,
                isFlying: false, selectedMaterial: .grass,
                solidWords: [], materials: [:]))
        var data = base
        // Count of materials: 0 → change to 1 and append bad entry.
        let countOffset = 4 + 4 + 4 + 8 + 12 + 4 + 4 + 1 + 1 + 4
        // Write materialCount = 1
        data[countOffset] = 1
        data[countOffset + 1] = 0
        data[countOffset + 2] = 0
        data[countOffset + 3] = 0
        // Append cellIndex LE = 0
        data.append(contentsOf: [0, 0, 0, 0])
        // Append bad material code (99)
        data.append(99)
        #expect(WorldSaveCodec.decode(data) == nil)
    }

    @Test
    func outOfRangeCellIndexReturnsNil() {
        var data = WorldSaveCodec.encode(
            WorldSaveState(
                gridSize: 8, chunkSize: 4, seed: 0,
                playerPosition: .zero, cameraYaw: 0, cameraPitch: 0,
                isFlying: false, selectedMaterial: .grass,
                solidWords: [], materials: [:]))
        // Replace materialCount 0 with 1 + an entry with cellIndex > (8³).
        let countOffset = 4 + 4 + 4 + 8 + 12 + 4 + 4 + 1 + 1 + 4
        data[countOffset] = 1
        data[countOffset + 1] = 0
        data[countOffset + 2] = 0
        data[countOffset + 3] = 0
        // cellIndex = 8*8*8 = 512 (out of range)
        var cell: UInt32 = 512
        Swift.withUnsafeBytes(of: &cell) { data.append(contentsOf: $0) }
        data.append(0)  // grass code
        #expect(WorldSaveCodec.decode(data) == nil)
    }
}
