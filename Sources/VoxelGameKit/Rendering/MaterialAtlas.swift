import Metal
import simd

// The demo uses a tiny procedural texture atlas so we can show textured materials without
// needing external image assets. Some faces still use flat colors, so the shader can skip the
// texture lookup for those vertices.
struct MaterialAtlas {
    enum Tile {
        case grass
        case dirt
        case stone
        case moss
    }

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
        let atlasSize = 16
        let bytesPerPixel = 4
        let bytesPerRow = atlasSize * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: atlasSize * atlasSize * bytesPerPixel)

        Self.drawTile(into: &pixels, atlasSize: atlasSize, tileX: 0, tileY: 0) { x, y in
            ((x + y) % 2 == 0) ? SIMD4<UInt8>(64, 168, 54, 255) : SIMD4<UInt8>(78, 186, 68, 255)
        }
        Self.drawTile(into: &pixels, atlasSize: atlasSize, tileX: 1, tileY: 0) { x, y in
            ((x * 3 + y * 5) % 4 == 0)
                ? SIMD4<UInt8>(120, 78, 42, 255)
                : SIMD4<UInt8>(99, 62, 33, 255)
        }
        Self.drawTile(into: &pixels, atlasSize: atlasSize, tileX: 0, tileY: 1) { x, y in
            ((x * 7 + y * 11) % 5 == 0)
                ? SIMD4<UInt8>(153, 153, 160, 255)
                : SIMD4<UInt8>(126, 126, 132, 255)
        }
        Self.drawTile(into: &pixels, atlasSize: atlasSize, tileX: 1, tileY: 1) { x, y in
            ((x + 2 * y) % 3 == 0)
                ? SIMD4<UInt8>(82, 120, 82, 255)
                : SIMD4<UInt8>(62, 99, 62, 255)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: true)
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererSetupError.materialAtlasUnavailable
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, atlasSize, atlasSize),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow)

        // The atlas is intentionally tiny and high-contrast, which makes distant surfaces prone to
        // shimmer if we only ever sample mip level 0. Generate the mip chain once at startup so
        // the shader can use trilinear minification without per-frame work.
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

    static func region(for tile: Tile) -> Region {
        let tileSize: Float = 0.5
        switch tile {
        case .grass:
            return Region(minUV: SIMD2(0.0, 0.0), maxUV: SIMD2(tileSize, tileSize))
        case .dirt:
            return Region(minUV: SIMD2(tileSize, 0.0), maxUV: SIMD2(1.0, tileSize))
        case .stone:
            return Region(minUV: SIMD2(0.0, tileSize), maxUV: SIMD2(tileSize, 1.0))
        case .moss:
            return Region(minUV: SIMD2(tileSize, tileSize), maxUV: SIMD2(1.0, 1.0))
        }
    }

    private static func drawTile(
        into pixels: inout [UInt8],
        atlasSize: Int,
        tileX: Int,
        tileY: Int,
        colorAt: (Int, Int) -> SIMD4<UInt8>
    ) {
        let tileSize = atlasSize / 2

        for localY in 0..<tileSize {
            for localX in 0..<tileSize {
                let atlasX = tileX * tileSize + localX
                let atlasY = tileY * tileSize + localY
                let pixelIndex = (atlasY * atlasSize + atlasX) * 4
                let color = colorAt(localX, localY)

                pixels[pixelIndex + 0] = color.x
                pixels[pixelIndex + 1] = color.y
                pixels[pixelIndex + 2] = color.z
                pixels[pixelIndex + 3] = color.w
            }
        }
    }
}
