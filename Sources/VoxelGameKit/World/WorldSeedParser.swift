import Foundation

/// Turns user text into a world seed: numeric strings are used directly,
/// anything else is hashed (FNV-1a 64) so any phrase is a valid seed.
///
/// This lets the "New World from Seed…" dialog accept both `12345` and
/// `glacier ridge` — the same text always produces the same world.
public enum WorldSeedParser {
    public static func seed(from text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let numeric = UInt64(trimmed) { return numeric }

        // FNV-1a 64-bit hash: simple, fast, and deterministic across launches.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // offset basis
        for byte in trimmed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3  // FNV prime
        }
        return hash
    }
}
