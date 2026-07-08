import Testing
import VoxelEngine

struct BitGridTests {
    // MARK: - Set / get round-trip

    @Test
    func setGetRoundTrip() {
        var grid = BitGrid(count: 200)

        // Set a spread of indices that cross word boundaries.
        grid[0] = true
        grid[63] = true
        grid[64] = true
        grid[65] = true
        grid[199] = true

        // Round-trip: each set index reads back true.
        #expect(grid[0])
        #expect(grid[63])
        #expect(grid[64])
        #expect(grid[65])
        #expect(grid[199])

        // Neighbors remain untouched (false).
        #expect(!grid[1])
        #expect(!grid[62])
        #expect(!grid[66])
    }

    // MARK: - Clear

    @Test
    func clearBit() {
        var grid = BitGrid(count: 200)

        grid[42] = true
        #expect(grid[42])

        grid[42] = false
        #expect(!grid[42])
    }

    // MARK: - Packing size

    @Test
    func packingSize() {
        // 128 bits = exactly 2 words (no partial).
        #expect(BitGrid(count: 128).words.count == 2)
        // 129 bits = 3 words (last word partially used).
        #expect(BitGrid(count: 129).words.count == 3)
    }

    // MARK: - Equality

    @Test
    func equalityBitForBitIdentical() {
        var a = BitGrid(count: 200)
        var b = BitGrid(count: 200)

        a[7] = true
        a[100] = true

        b[7] = true
        b[100] = true

        #expect(a == b)
    }

    @Test
    func inequalityDifferingByOneBit() {
        var a = BitGrid(count: 200)
        var b = BitGrid(count: 200)

        a[7] = true
        a[100] = true

        b[7] = true
        // b[100] left false — one-bit difference.

        #expect(a != b)
    }

    // MARK: - Edge: zero count

    @Test
    func zeroCountProducesEmptyWords() {
        let grid = BitGrid(count: 0)
        #expect(grid.words.count == 0)
    }
}
