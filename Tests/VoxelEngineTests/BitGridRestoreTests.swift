import Testing
import VoxelEngine

struct BitGridRestoreTests {

    @Test
    func validWordsRoundTripSubscript() {
        let grid = BitGrid(
            count: 200,
            words: [
                1 << 5,  // word 0, bit 5 set
                0,
                1 << 7,  // word 2, bit 7 set
                0b1111,  // word 3, low 4 bits set
            ])
        #expect(grid != nil)
        let g = grid!
        #expect(g[5] == true)
        #expect(g[4] == false)
        #expect(g[135] == true)  // word 2 * 64 + 7
        #expect(g[192] == true)  // word 3, bit 0
        #expect(g[195] == true)  // word 3, bit 3
        #expect(g[196] == false)
    }

    @Test
    func wrongWordLengthReturnsNil() {
        // 200 bits need ceil(200/64) = 4 words. 3 words is too few.
        #expect(BitGrid(count: 200, words: [0, 0, 0]) == nil)
    }

    @Test
    func nonzeroTrailingBitsReturnsNil() {
        // 200 bits → last word uses bits 0..7 (200 % 64 = 8). Bit 8 must be zero.
        var words: [UInt64] = [0, 0, 0, 0]
        words[3] = 1 << 10  // bit 10 is beyond the 200-bit boundary
        #expect(BitGrid(count: 200, words: words) == nil)
    }

    @Test
    func exactMultipleOf64Acceptable() {
        let grid = BitGrid(count: 128, words: [0, 1 << 63])
        #expect(grid != nil)
        #expect(grid![127] == true)
    }
}
