import Metal
import simd

// The engine ships a tiny procedural texture atlas so textured materials work without any
// external image assets — staying true to the "zero binary assets" soul of the project.
// Some faces still use flat colors, so the shader can skip the texture lookup for those
// vertices.
//
// The atlas is a grid of `columns` x `rows` tiles, each `tileSize` pixels square. Tiles are
// packed left-to-right, top-to-bottom in `Tile` order below.
struct MaterialAtlas {
    enum Tile {
        case grass
        case dirt
        case stone
        case moss
        case sand
        case wood  // trunk bark (sides)
        case woodTop  // trunk end grain (top/bottom)
        case leaves
    }

    // 4 columns x 2 rows = 8 tiles. Keeping tiles at 8x8 (same as the original 2x2 atlas)
    // preserves the existing look/mip behavior; we just add a second row of tiles.
    private static let columns = 4
    private static let rows = 2
    private static let tileSize = 8
    private static var atlasWidth: Int { columns * tileSize }
    private static var atlasHeight: Int { rows * tileSize }

    struct Region {
        let minUV: SIMD2<Float>
        let maxUV: SIMD2<Float>

        var quadUVs: [SIMD2<Float>] {
            [
                SIMD2(minUV.x, maxUV.y),
                SIMD2(maxUV.x, maxUV.y),
                SIMD2(maxUV.x, minUV.y),
                SIMD2(minUV.x, minUV.y),
            ]
        }
    }

    let texture: MTLTexture

    init(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        let width = Self.atlasWidth
        let height = Self.atlasHeight
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: width * height * bytesPerPixel)

        // Row 0 — the original ground tiles.
        Self.drawTile(into: &pixels, tile: .grass) { x, y in
            ((x + y) % 2 == 0) ? SIMD4<UInt8>(64, 168, 54, 255) : SIMD4<UInt8>(78, 186, 68, 255)
        }
        Self.drawTile(into: &pixels, tile: .dirt) { x, y in
            ((x * 3 + y * 5) % 4 == 0)
                ? SIMD4<UInt8>(120, 78, 42, 255)
                : SIMD4<UInt8>(99, 62, 33, 255)
        }
        Self.drawTile(into: &pixels, tile: .stone) { x, y in
            ((x * 7 + y * 11) % 5 == 0)
                ? SIMD4<UInt8>(153, 153, 160, 255)
                : SIMD4<UInt8>(126, 126, 132, 255)
        }
        Self.drawTile(into: &pixels, tile: .moss) { x, y in
            ((x + 2 * y) % 3 == 0)
                ? SIMD4<UInt8>(82, 120, 82, 255)
                : SIMD4<UInt8>(62, 99, 62, 255)
        }

        // Row 1 — the new tiles.
        // Sand: soft speckled tan.
        Self.drawTile(into: &pixels, tile: .sand) { x, y in
            ((x * 5 + y * 3) % 7 == 0)
                ? SIMD4<UInt8>(224, 208, 152, 255)
                : SIMD4<UInt8>(214, 196, 138, 255)
        }
        // Wood bark: vertical streaks (color varies mostly along x).
        Self.drawTile(into: &pixels, tile: .wood) { x, _ in
            (x % 3 == 0)
                ? SIMD4<UInt8>(86, 58, 32, 255)
                : SIMD4<UInt8>(104, 72, 40, 255)
        }
        // Wood end grain: concentric-ish rings around the tile center.
        Self.drawTile(into: &pixels, tile: .woodTop) { x, y in
            ((abs(x - 3) + abs(y - 3)) % 2 == 0)
                ? SIMD4<UInt8>(140, 104, 62, 255)
                : SIMD4<UInt8>(120, 86, 50, 255)
        }
        // Leaves: dithered greens, lighter than moss so foliage reads as canopy.
        Self.drawTile(into: &pixels, tile: .leaves) { x, y in
            ((x * 2 + y) % 3 == 0)
                ? SIMD4<UInt8>(74, 132, 58, 255)
                : SIMD4<UInt8>(56, 106, 44, 255)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: true)
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererSetupError.materialAtlasUnavailable
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow)

        // The atlas is intentionally tiny and high-contrast, which makes distant surfaces prone to
        // shimmer if we only ever sample mip level 0. Generate the mip chain once at startup so
        // the shader can use trilinear minification without per-frame work. (Adjacent tiles bleed
        // slightly at the coarsest mips — an accepted tradeoff shared by the original 2x2 atlas.)
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        else {
            throw RendererSetupError.materialAtlasUnavailable
        }

        blitEncoder.generateMipmaps(for: texture)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            throw RendererSetupError.materialAtlasUnavailable
        }

        self.texture = texture
    }

    /// The (column, row) slot each tile occupies in the atlas grid.
    private static func slot(for tile: Tile) -> (column: Int, row: Int) {
        switch tile {
        case .grass: return (0, 0)
        case .dirt: return (1, 0)
        case .stone: return (2, 0)
        case .moss: return (3, 0)
        case .sand: return (0, 1)
        case .wood: return (1, 1)
        case .woodTop: return (2, 1)
        case .leaves: return (3, 1)
        }
    }

    static func region(for tile: Tile) -> Region {
        let (column, row) = slot(for: tile)
        let tileWidth = 1.0 / Float(columns)
        let tileHeight = 1.0 / Float(rows)
        let minUV = SIMD2<Float>(Float(column) * tileWidth, Float(row) * tileHeight)
        let maxUV = SIMD2<Float>(minUV.x + tileWidth, minUV.y + tileHeight)
        return Region(minUV: minUV, maxUV: maxUV)
    }

    private static func drawTile(
        into pixels: inout [UInt8],
        tile: Tile,
        colorAt: (Int, Int) -> SIMD4<UInt8>
    ) {
        let (column, row) = slot(for: tile)
        let originX = column * tileSize
        let originY = row * tileSize

        for localY in 0..<tileSize {
            for localX in 0..<tileSize {
                let atlasX = originX + localX
                let atlasY = originY + localY
                let pixelIndex = (atlasY * atlasWidth + atlasX) * 4
                let color = colorAt(localX, localY)

                pixels[pixelIndex + 0] = color.x
                pixels[pixelIndex + 1] = color.y
                pixels[pixelIndex + 2] = color.z
                pixels[pixelIndex + 3] = color.w
            }
        }
    }
}
