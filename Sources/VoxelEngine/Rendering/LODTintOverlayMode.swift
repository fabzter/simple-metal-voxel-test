public enum LODTintOverlayMode: CaseIterable, Sendable {
    case off
    case bands

    public var displayName: String {
        switch self {
        case .off:
            return "LOD tint off"
        case .bands:
            return "LOD tint bands"
        }
    }
}
