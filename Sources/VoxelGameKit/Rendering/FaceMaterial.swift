import simd

enum FaceMaterial {
    case flat(color: SIMD3<Float>, previewTile: MaterialAtlas.Tile)
    case textured(tile: MaterialAtlas.Tile, tint: SIMD3<Float>)

    var uvQuad: [SIMD2<Float>] {
        switch self {
        case .flat(_, let previewTile):
            return MaterialAtlas.region(for: previewTile).quadUVs
        case .textured(let tile, _):
            return MaterialAtlas.region(for: tile).quadUVs
        }
    }

    func vertex(position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) -> Vertex {
        switch self {
        case .flat(let color, _):
            return Vertex(
                position: position,
                normal: normal,
                color: color,
                uv: uv,
                materialMode: MaterialMode.flatColor.rawValue)
        case .textured(_, let tint):
            return Vertex(
                position: position,
                normal: normal,
                color: tint,
                uv: uv,
                materialMode: MaterialMode.textured.rawValue)
        }
    }
}
