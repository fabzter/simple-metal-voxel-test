import Foundation

// MARK: - Why this type exists
//
// A `[Bool]` in Swift stores one byte per boolean. For a 256³ voxel world that's
// 16,777,216 bytes = ~16 MiB — even though most cells are empty (air).  BitGrid
// packs each cell into a single bit inside a [UInt64] array, shrinking the same
// grid to ~2 MiB — an 8× reduction.  The smaller footprint also fits better in
// CPU caches, which can speed up the meshing pass that scans every cell.

/// A fixed-size array of bits backed by packed `UInt64` words.
///
/// Use it like an array of Booleans with a subscript, but each element costs one
/// bit instead of one byte.  Indices are zero-based.  Callers guarantee that any
/// index passed to the subscript is in `0 ..< count`; there is no bounds check
/// inside the subscript (matching the `[Bool]` behaviour this type replaces).
///
/// ## How the packing works
///
/// 64 bits fit in one `UInt64`.  Given a cell index:
///
/// - `index >> 6`  (divide by 64) picks the word.
/// - `index & 63`  (modulo 64)  picks the bit inside that word.
///
/// Example: index 65 → word 1 (65 / 64 = 1), bit 1 (65 % 64 = 1).
///
/// ## Why Equatable works on rounded-up words
///
/// The last word may have unused high bits (when `count` is not a multiple of 64).
/// Those bits are always zero because bits are only ever **set** for in-range
/// indices and every setter is guarded by an external bounds check.  Two grids
/// with the same data therefore have byte-for-byte identical `words` arrays.
public struct BitGrid: Equatable, Sendable {

    /// Packed bit storage — 64 voxels per `UInt64`.
    public private(set) var words: [UInt64]

    /// Number of addressable bits (voxels).  Always non-negative.
    public let count: Int

    // MARK: - Lifecycle

    /// Creates a zero-filled bit grid with room for `count` elements.
    ///
    /// - Parameter count: Must be ≥ 0.  The backing array is `(count + 63) / 64`
    ///   words, all initialized to zero.
    public init(count: Int) {
        precondition(count >= 0, "BitGrid count must be non-negative, got \(count)")
        self.count = count
        self.words = Array(repeating: 0, count: (count + 63) / 64)
    }

    /// Restores a BitGrid from previously saved word data.  Returns `nil` when the
    /// word count does not match the expected packing, or when unused trailing bits
    /// in the last word are non-zero (they must be zero per the `Equatable` invariant).
    public init?(count: Int, words: [UInt64]) {
        let expected = (count + 63) / 64
        guard words.count == expected else { return nil }
        if count > 0 {
            let lastWord = words[expected - 1]
            let usedBits = count & 63
            if usedBits != 0 {
                let trailingMask = ~UInt64(0) << usedBits
                guard (lastWord & trailingMask) == 0 else { return nil }
            }
        }
        self.count = count
        self.words = words
    }

    // MARK: - Element access

    /// Reads or writes the bit at `index`.
    ///
    /// - Precondition: `0 <= index < count`.  The caller (typically `VoxelWorld`)
    ///   performs its own bounds check before reaching this subscript.
    public subscript(_ index: Int) -> Bool {
        get {
            // BitGrid invariant: index is always in 0..<count.
            (words[index >> 6] >> UInt64(index & 63)) & 1 == 1
        }
        set {
            let wordIndex = index >> 6
            let bitMask = UInt64(1) << UInt64(index & 63)
            if newValue {
                words[wordIndex] |= bitMask
            } else {
                words[wordIndex] &= ~bitMask
            }
        }
    }
}
