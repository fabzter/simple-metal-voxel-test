import simd

/// The palette of block surfaces a player can build with.
///
/// This is the engine's reusable block vocabulary: the terrain generator, the mesher,
/// the save codec, and any palette UI all read from these cases. Adding a case here and
/// letting the compiler flag every non-exhaustive `switch` is the intended way to grow
/// the palette safely.
public enum BlockMaterialType: String, CaseIterable, Sendable {
    case grass
    case dirt
    case stone
    case moss
    case snow
    case sand
    case wood
    case leaves

    public var displayName: String {
        rawValue.capitalized
    }

    /// A single representative color for this material, for palette/hotbar swatches and
    /// any other UI that needs to show the block without rendering a 3D face. Kept here
    /// (not in the demo) so the color stays in sync with the material itself and any UI —
    /// engine or demo — can reuse it.
    public var swatchColor: SIMD3<Float> {
        switch self {
        case .grass: return SIMD3<Float>(0.30, 0.70, 0.28)
        case .dirt: return SIMD3<Float>(0.42, 0.28, 0.16)
        case .stone: return SIMD3<Float>(0.58, 0.60, 0.64)
        case .moss: return SIMD3<Float>(0.36, 0.52, 0.34)
        case .snow: return SIMD3<Float>(0.94, 0.96, 1.00)
        case .sand: return SIMD3<Float>(0.90, 0.82, 0.60)
        case .wood: return SIMD3<Float>(0.52, 0.37, 0.20)
        case .leaves: return SIMD3<Float>(0.30, 0.56, 0.24)
        }
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
        case .sand:
            return .textured(tile: .sand, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        case .wood:
            return .textured(tile: .wood, tint: SIMD3<Float>(1.0, 1.0, 1.0))
        case .leaves:
            return .textured(tile: .leaves, tint: SIMD3<Float>(0.95, 1.0, 0.95))
        }
    }
}
