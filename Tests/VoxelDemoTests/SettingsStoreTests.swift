import Foundation
import Testing

@testable import VoxelDemo

struct SettingsStoreTests {
    /// Each test gets an isolated defaults suite so settings never bleed across runs.
    private func makeStore() -> (SettingsStore, UserDefaults) {
        let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test
    func defaultsFillEmptyStore() {
        let (store, _) = makeStore()

        #expect(store.lookSensitivity == 0.005)
        #expect(store.fieldOfViewDegrees == 65)
        #expect(store.soundEnabled)
        #expect(store.masterVolume == 1)
        #expect(!store.invertLookY)
        #expect(store.renderScale == 1)
        #expect(store.aspectRatio == .free)
    }

    @Test
    func writesRoundTripAcrossAllSettings() {
        var (store, _) = makeStore()

        store.lookSensitivity = 0.009
        store.fieldOfViewDegrees = 82
        store.soundEnabled = false
        store.masterVolume = 0.35
        store.invertLookY = true
        store.renderScale = 1.5
        store.aspectRatio = .wide16x10

        #expect(store.lookSensitivity == 0.009)
        #expect(store.fieldOfViewDegrees == 82)
        #expect(!store.soundEnabled)
        #expect(store.masterVolume == 0.35)
        #expect(store.invertLookY)
        #expect(store.renderScale == 1.5)
        #expect(store.aspectRatio == .wide16x10)
    }

    @Test
    func settersClampIntoSupportedRanges() {
        var (store, _) = makeStore()

        store.lookSensitivity = 1
        store.fieldOfViewDegrees = 10
        store.masterVolume = -2
        store.renderScale = 9

        #expect(store.lookSensitivity == 0.012)
        #expect(store.fieldOfViewDegrees == 50)
        #expect(store.masterVolume == 0)
        #expect(store.renderScale == 2)
    }

    @Test
    func legacyKeysStillReadThroughFacade() {
        let (_, defaults) = makeStore()
        defaults.set(Float(80), forKey: "settings.fieldOfViewDegrees")

        let store = SettingsStore(defaults: defaults)
        #expect(store.fieldOfViewDegrees == 80)
    }
}
