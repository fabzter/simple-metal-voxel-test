import AppKit

/// Native aspect-ratio presets for the main window. Stored in preferences so the
/// window can restore the same resize behavior on relaunch.
enum WindowAspectRatio: String, CaseIterable {
    case free
    case wide16x9 = "16:9"
    case wide16x10 = "16:10"
    case classic4x3 = "4:3"

    var displayName: String {
        switch self {
        case .free:
            return "Free"
        case .wide16x9:
            return "16:9"
        case .wide16x10:
            return "16:10"
        case .classic4x3:
            return "4:3"
        }
    }

    var size: NSSize? {
        switch self {
        case .free:
            return nil
        case .wide16x9:
            return NSSize(width: 16, height: 9)
        case .wide16x10:
            return NSSize(width: 16, height: 10)
        case .classic4x3:
            return NSSize(width: 4, height: 3)
        }
    }
}
