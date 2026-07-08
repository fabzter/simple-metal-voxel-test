public enum MaterialDebugMode: Float, CaseIterable, Sendable {
    case hybrid = 0
    case flatColorsOnly = 1
    case texturesOnly = 2

    public var displayName: String {
        switch self {
        case .hybrid:
            return "Textured + flat-color"
        case .flatColorsOnly:
            return "Flat colors only"
        case .texturesOnly:
            return "Textures only"
        }
    }

    public func next() -> MaterialDebugMode {
        switch self {
        case .hybrid:
            return .flatColorsOnly
        case .flatColorsOnly:
            return .texturesOnly
        case .texturesOnly:
            return .hybrid
        }
    }
}
