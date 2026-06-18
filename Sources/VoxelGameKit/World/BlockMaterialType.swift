import simd

public enum BlockMaterialType: String, CaseIterable, Sendable {
    case grass
    case dirt
    case stone
    case moss
    case snow

    public var displayName: String {
        rawValue.capitalized
    }

    var faceMaterial: FaceMaterial {
        switch self {
        case .grass:
            return .textured(tile: .grass, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        case .dirt:
            return .textured(tile: .dirt, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        case .stone:
            return .flat(color: SIMD3<Float>(0.58, 0.60, 0.64), previewTile: .stone)
        case .moss:
            return .textured(tile: .moss, tint: SIMD3<Float>(0.95, 0.95, 0.95))
        case .snow:
            return .flat(color: SIMD3<Float>(0.94, 0.96, 1.0), previewTile: .stone)
        }
    }
}
