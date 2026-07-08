import CoreGraphics
import Metal
import QuartzCore
import Testing
import simd

@testable import VoxelEngine

/// Tests for the LOD crossfade fade lifecycle, edit cancellation, and renderer reset.
/// These extend the existing RendererCacheTests headless-CAMetalLayer harness.
struct RendererFadeTests {

    private func makeDevice() -> (MTLDevice, CGSize, CAMetalLayer)? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device unavailable.")
            return nil
        }
        let size = CGSize(width: 64, height: 64)
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.drawableSize = size
        return (device, size, layer)
    }

    private func makeRenderer(device: MTLDevice, drawableSize: CGSize) throws -> Renderer {
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .terrain(.default))
        let lod = LODConfiguration(levels: [
            .init(maxChunkDistance: 2, voxelStride: 1),
            .init(maxChunkDistance: 3, voxelStride: 2),
            .init(maxChunkDistance: 6, voxelStride: 4),
        ])
        let renderer = try Renderer(
            device: device, world: world, drawableSize: drawableSize, lodConfiguration: lod)
        var debug = RenderDebugSettings()
        debug.frustumCullingEnabled = false
        debug.occlusionCullingEnabled = false
        renderer.debugSettings = debug
        return renderer
    }

    @Test
    func fadeTriggersThenExpires() throws {
        guard let (device, size, layer) = makeDevice() else { return }
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .terrain(.default))
        let renderer = try makeRenderer(device: device, drawableSize: size)

        var fakeNow: Double = 0
        renderer.timeSource = { fakeNow }

        // Render once to settle the cache.
        let camA = CameraState(position: SIMD3<Float>(8, 40, 8), yaw: 0, pitch: -0.6)
        try renderer.render(
            into: layer, world: world, camera: camA,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        #expect(renderer.activeFadeCount == 0)

        // Move far enough that some chunks change LOD → triggers fade entries.
        let camB = CameraState(position: SIMD3<Float>(56, 40, 56), yaw: 2.4, pitch: -0.6)
        try renderer.render(
            into: layer, world: world, camera: camB,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        #expect(renderer.activeFadeCount > 0)

        // Advance past the 0.25 s fade duration.
        fakeNow += 0.3
        try renderer.render(
            into: layer, world: world, camera: camB,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        #expect(renderer.activeFadeCount == 0)
    }

    @Test
    func editCancelsFade() throws {
        guard let (device, size, layer) = makeDevice() else { return }
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .terrain(.default))
        let renderer = try makeRenderer(device: device, drawableSize: size)

        let camA = CameraState(position: SIMD3<Float>(8, 40, 8), yaw: 0, pitch: -0.6)
        let camB = CameraState(position: SIMD3<Float>(56, 40, 56), yaw: 2.4, pitch: -0.6)
        try renderer.render(
            into: layer, world: world, camera: camA,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        try renderer.render(
            into: layer, world: world, camera: camB,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)

        // Find a fading chunk.
        var fadingChunk: VoxelChunkIndex?
        for ci in world.allChunkIndices() where renderer.isFading(ci) {
            fadingChunk = ci
            break
        }
        guard let fc = fadingChunk else {
            Issue.record("No fading chunk found to test edit cancellation.")
            return
        }

        // Edit inside the fading chunk.
        let cx = fc.x * world.chunkSize + 4
        let cy = fc.y * world.chunkSize + 4
        let cz = fc.z * world.chunkSize + 4
        world.setSolid(!world.isSolid(x: cx, y: cy, z: cz), x: cx, y: cy, z: cz)
        try renderer.render(
            into: layer, world: world, camera: camB,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        #expect(!renderer.isFading(fc))
    }

    @Test
    func rendererResetClearsAllCaches() throws {
        guard let (device, size, layer) = makeDevice() else { return }
        let world = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .terrain(.default))
        let renderer = try makeRenderer(device: device, drawableSize: size)

        let cam = CameraState(position: SIMD3<Float>(32, 40, 32), yaw: 0, pitch: -0.6)
        try renderer.render(
            into: layer, world: world, camera: cam,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        #expect(renderer.meshBufferCacheCount > 0)

        let freshWorld = VoxelWorld(gridSize: 64, chunkSize: 16, generation: .empty)
        renderer.resetWorldSynchronization(with: freshWorld)
        #expect(renderer.meshBufferCacheCount == 0)
        #expect(renderer.activeFadeCount == 0)

        // Repopulate after reset.
        try renderer.render(
            into: layer, world: freshWorld, camera: cam,
            selectedHit: nil as VoxelRaycastHit?, editFeedback: nil as EditFeedback?)
        #expect(renderer.meshBufferCacheCount > 0)
    }
}
