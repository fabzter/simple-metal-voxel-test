import CoreGraphics
import Metal
import QuartzCore
import Testing
import simd

@testable import VoxelEngine

struct RendererCacheTests {

    // MARK: - Helpers

    private func makeDevice() -> (MTLDevice, CGSize, CAMetalLayer)? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device unavailable for cache test.")
            return nil
        }
        let size = CGSize(width: 64, height: 64)
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.drawableSize = size
        return (device, size, layer)
    }

    /// Builds a 64³ world (4×4×4 = 64 chunks) with culling off so every chunk
    /// reaches the meshBuffer cache regardless of camera position.
    private func makeRenderer(
        device: MTLDevice,
        drawableSize: CGSize,
        generation: VoxelWorld.Generation = .terrain(.default)
    ) throws -> Renderer {
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: generation)
        let lod = LODConfiguration(levels: [
            .init(maxChunkDistance: 2, voxelStride: 1),
            .init(maxChunkDistance: 3, voxelStride: 2),
            .init(maxChunkDistance: 6, voxelStride: 4),
        ])
        let renderer = try Renderer(
            device: device,
            world: world,
            drawableSize: drawableSize,
            lodConfiguration: lod)
        var debug = RenderDebugSettings()
        debug.frustumCullingEnabled = false
        debug.occlusionCullingEnabled = false
        renderer.debugSettings = debug
        return renderer
    }

    // MARK: - Cache growth

    @Test
    func movingCameraNeverGrowsCachePastChunkCount() throws {
        guard let (device, size, layer) = makeDevice() else { return }
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .terrain(.default))
        let renderer = try makeRenderer(device: device, drawableSize: size)

        let camA = CameraState(position: SIMD3<Float>(8, 40, 8), yaw: 0, pitch: -0.6)
        let camB = CameraState(position: SIMD3<Float>(56, 40, 56), yaw: 2.4, pitch: -0.6)

        for _ in 0..<6 {
            try renderer.render(
                into: layer, world: world, camera: camA,
                selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
            try renderer.render(
                into: layer, world: world, camera: camB,
                selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        }

        // The world has exactly 64 chunks. Without per-chunk eviction, boundary chunks
        // accumulate multiple seam-config keys and the cache bloats past 64.
        #expect(renderer.meshBufferCacheCount <= 64)
    }

    @Test
    func chunkKeepsExactlyOneCachedMesh() throws {
        guard let (device, size, layer) = makeDevice() else { return }
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .terrain(.default))
        let renderer = try makeRenderer(device: device, drawableSize: size)

        let camA = CameraState(position: SIMD3<Float>(8, 40, 8), yaw: 0, pitch: -0.6)
        let camB = CameraState(position: SIMD3<Float>(56, 40, 56), yaw: 2.4, pitch: -0.6)

        for _ in 0..<4 {
            try renderer.render(
                into: layer, world: world, camera: camA,
                selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
            try renderer.render(
                into: layer, world: world, camera: camB,
                selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        }

        for chunkIndex in world.allChunkIndices() {
            #expect(renderer.cachedLODKeys(for: chunkIndex).count <= 1)
        }
    }

    // MARK: - Empty-chunk sentinel

    @Test
    func emptyChunksShareOneSentinelBuffer() throws {
        guard let (device, size, layer) = makeDevice() else { return }
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .empty)
        let renderer = try makeRenderer(
            device: device, drawableSize: size, generation: .empty)

        let cam = CameraState(position: SIMD3<Float>(32, 32, 32), yaw: 0, pitch: 0)
        try renderer.render(
            into: layer, world: world, camera: cam,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)

        #expect(renderer.meshBufferCacheCount == 64)
        #expect(renderer.currentVertexCount == 0)
        #expect(renderer.cachedBuffersAreAllIdentical())
    }
}
