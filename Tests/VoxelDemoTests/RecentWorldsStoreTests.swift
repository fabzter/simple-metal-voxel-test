import Foundation
import Testing

@testable import VoxelDemo

struct RecentWorldsStoreTests {
    /// Each test gets an isolated defaults suite so runs never interfere.
    private func makeStore(limit: Int = 8) -> (RecentWorldsStore, UserDefaults) {
        let suiteName = "RecentWorldsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (RecentWorldsStore(defaults: defaults, limit: limit), defaults)
    }

    @Test
    func notesAreMostRecentFirst() {
        let (store, _) = makeStore()
        store.note("/a")
        store.note("/b")
        store.note("/c")
        #expect(store.paths() == ["/c", "/b", "/a"])
    }

    @Test
    func notingAnExistingPathMovesItToFront() {
        let (store, _) = makeStore()
        store.note("/a")
        store.note("/b")
        store.note("/a")
        #expect(store.paths() == ["/a", "/b"])
    }

    @Test
    func listIsCappedAtLimit() {
        let (store, _) = makeStore(limit: 3)
        for i in 0..<5 {
            store.note("/world-\(i)")
        }
        #expect(store.paths() == ["/world-4", "/world-3", "/world-2"])
    }

    @Test
    func removeDropsOnlyThatPath() {
        let (store, _) = makeStore()
        store.note("/a")
        store.note("/b")
        store.remove("/a")
        #expect(store.paths() == ["/b"])
    }

    @Test
    func clearEmptiesTheList() {
        let (store, _) = makeStore()
        store.note("/a")
        store.clear()
        #expect(store.paths().isEmpty)
    }
}
