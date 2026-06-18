public enum LODTintOverlayMode: CaseIterable, Sendable {
    case off
    case subtle

    public var displayName: String {
        switch self {
        case .off:
            return "LOD tint off"
        case .subtle:
            return "LOD tint subtle"
        }
    }
}
