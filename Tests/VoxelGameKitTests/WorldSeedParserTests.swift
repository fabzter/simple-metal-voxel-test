import Testing
import VoxelGameKit

struct WorldSeedParserTests {

    @Test
    func numericStringsPassThrough() {
        #expect(WorldSeedParser.seed(from: "12345") == 12345)
        #expect(WorldSeedParser.seed(from: " 42 ") == 42)
    }

    @Test
    func textHashesDeterministically() {
        let first = WorldSeedParser.seed(from: "glacier")
        let second = WorldSeedParser.seed(from: "glacier")
        #expect(first != nil)
        #expect(first == second)
        #expect(first != WorldSeedParser.seed(from: "glacier2"))
    }

    @Test
    func emptyAndWhitespaceAreRejected() {
        #expect(WorldSeedParser.seed(from: "") == nil)
        #expect(WorldSeedParser.seed(from: "   ") == nil)
    }

    @Test
    func overflowingDigitsFallBackToHashing() {
        // Larger than UInt64.max, so UInt64(_:) fails and the hash path takes over.
        #expect(WorldSeedParser.seed(from: "99999999999999999999999") != nil)
    }
}
