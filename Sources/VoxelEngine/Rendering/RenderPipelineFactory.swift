import Metal
import simd

struct RenderPipelineFactory {
    static func makePipelineState(device: MTLDevice, library: MTLLibrary) throws
        -> MTLRenderPipelineState
    {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.attributes[2].format = .float3
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0

        vertexDescriptor.attributes[3].format = .float2
        vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD3<Float>>.stride * 3
        vertexDescriptor.attributes[3].bufferIndex = 0

        vertexDescriptor.attributes[4].format = .float
        vertexDescriptor.attributes[4].offset =
            MemoryLayout<SIMD3<Float>>.stride * 3 + MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[4].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererSetupError.pipelineStateUnavailable(error)
        }
    }

    static func makeHighlightPipelineState(device: MTLDevice, library: MTLLibrary) throws
        -> MTLRenderPipelineState
    {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_highlight")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_highlight")
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererSetupError.pipelineStateUnavailable(error)
        }
    }

    static func makeDepthState(device: MTLDevice) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true

        guard let depthState = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererSetupError.depthStateUnavailable
        }

        return depthState
    }

    /// Pipeline for the full-screen gradient sky. It takes no vertex buffer — the vertex
    /// shader generates one big triangle from `vertex_id` — so there is no vertex
    /// descriptor here. Drawn first each frame as the background behind the world.
    static func makeSkyPipelineState(device: MTLDevice, library: MTLLibrary) throws
        -> MTLRenderPipelineState
    {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_sky")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_sky")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererSetupError.pipelineStateUnavailable(error)
        }
    }

    /// Depth state for the sky: always passes and never writes depth, so the sky fills
    /// every background pixel without occluding the world drawn on top of it afterward.
    static func makeSkyDepthState(device: MTLDevice) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false

        guard let depthState = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererSetupError.depthStateUnavailable
        }

        return depthState
    }
}
