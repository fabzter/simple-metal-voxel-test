import Foundation

/// Tiny façade over UserDefaults so each persisted setting has one key, one default,
/// and one clamping rule instead of scattering those decisions across the app.
struct SettingsStore {
    static let lookSensitivityKey = "settings.lookSensitivity"
    static let fieldOfViewDegreesKey = "settings.fieldOfViewDegrees"
    static let soundEnabledKey = "settings.soundEnabled"
    static let masterVolumeKey = "settings.masterVolume"
    static let invertLookYKey = "settings.invertLookY"
    static let renderScaleKey = "settings.renderScale"
    static let aspectRatioKey = "settings.windowAspectRatio"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lookSensitivity: Float {
        get {
            let value = defaults.object(forKey: Self.lookSensitivityKey) as? Float ?? 0.005
            return value.clamped(to: 0.001...0.012)
        }
        set {
            defaults.set(newValue.clamped(to: 0.001...0.012), forKey: Self.lookSensitivityKey)
        }
    }

    var fieldOfViewDegrees: Float {
        get {
            let value = defaults.object(forKey: Self.fieldOfViewDegreesKey) as? Float ?? 65
            return value.clamped(to: 50...100)
        }
        set {
            defaults.set(newValue.clamped(to: 50...100), forKey: Self.fieldOfViewDegreesKey)
        }
    }

    var soundEnabled: Bool {
        get {
            defaults.object(forKey: Self.soundEnabledKey) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Self.soundEnabledKey)
        }
    }

    var masterVolume: Float {
        get {
            let value = defaults.object(forKey: Self.masterVolumeKey) as? Float ?? 1
            return value.clamped(to: 0...1)
        }
        set {
            defaults.set(newValue.clamped(to: 0...1), forKey: Self.masterVolumeKey)
        }
    }

    var invertLookY: Bool {
        get {
            defaults.object(forKey: Self.invertLookYKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Self.invertLookYKey)
        }
    }

    var renderScale: Float {
        get {
            let value = defaults.object(forKey: Self.renderScaleKey) as? Float ?? 1
            return value.clamped(to: 0.5...2.0)
        }
        set {
            defaults.set(newValue.clamped(to: 0.5...2.0), forKey: Self.renderScaleKey)
        }
    }

    var aspectRatio: WindowAspectRatio {
        get {
            guard
                let rawValue = defaults.string(forKey: Self.aspectRatioKey),
                let ratio = WindowAspectRatio(rawValue: rawValue)
            else {
                return .free
            }
            return ratio
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.aspectRatioKey)
        }
    }
}

extension Float {
    fileprivate func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
