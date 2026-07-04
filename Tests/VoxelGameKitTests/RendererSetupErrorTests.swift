import Foundation
import Metal
import Testing

@testable import VoxelGameKit

struct RendererSetupErrorTests {
    @Test
    func wrappedShaderLibraryErrorKeepsContext() {
        let wrapped = NSError(
            domain: "ShaderTests", code: 7,
            userInfo: [
                NSLocalizedDescriptionKey: "missing default library"
            ])

        let error = RendererSetupError.shaderLibraryUnavailable(wrapped)
        #expect(error.localizedDescription.contains("missing default library"))
    }

    @Test
    func meshBufferErrorIsReadable() {
        let error = RendererSetupError.meshBufferUnavailable
        #expect(error.localizedDescription == "Failed to allocate the world mesh buffer.")
    }

    @Test
    func materialAtlasBuildsMipChain() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device unavailable for atlas test.")
            return
        }
        guard let commandQueue = device.makeCommandQueue() else {
            Issue.record("Metal command queue unavailable for atlas test.")
            return
        }

        let atlas = try MaterialAtlas(device: device, commandQueue: commandQueue)
        #expect(atlas.texture.mipmapLevelCount > 1)
    }

    @Test
    func defaultLODStrideChainIsValid() {
        #expect(LODConfiguration.default.validateStrideChain() == nil)
    }

    @Test
    func nonDivisibleLODStridesAreRejected() {
        let config = LODConfiguration(levels: [
            .init(maxChunkDistance: 2, voxelStride: 3),
            .init(maxChunkDistance: 5, voxelStride: 5),
        ])
        #expect(config.validateStrideChain() != nil)
    }

    @Test
    func newLODDefaultDistancesMatchSpec() {
        let levels = LODConfiguration.default.levels
        #expect(levels.map(\.maxChunkDistance) == [4, 8, 13, 18])
        #expect(levels.map(\.voxelStride) == [1, 2, 4, 8])
    }

    @Test
    func powersOfTwoLODStrideChainIsValid() {
        let config = LODConfiguration(levels: [
            .init(maxChunkDistance: 2, voxelStride: 1),
            .init(maxChunkDistance: 5, voxelStride: 2),
            .init(maxChunkDistance: 9, voxelStride: 4),
            .init(maxChunkDistance: 18, voxelStride: 8),
        ])
        #expect(config.validateStrideChain() == nil)
    }
}
