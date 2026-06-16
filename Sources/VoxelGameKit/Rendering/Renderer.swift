import CoreGraphics
import Foundation
import Metal
import QuartzCore
import simd

public final class Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState
  private let vertexBuffer: MTLBuffer
  private let uniformsBuffer: MTLBuffer

  private let vertexCount: Int
  private var depthTexture: MTLTexture?

  public init(device: MTLDevice, world: VoxelWorld, drawableSize: CGSize) {
    guard let commandQueue = device.makeCommandQueue() else {
      fatalError("Failed to create command queue")
    }

    let worldMesh = world.buildMesh()

    guard
      let uniformsBuffer = device.makeBuffer(
        length: MemoryLayout<Uniforms>.stride,
        options: .storageModeShared)
    else {
      fatalError("Failed to allocate uniforms buffer")
    }

    guard
      let vertexBuffer = device.makeBuffer(
        bytes: worldMesh,
        length: MemoryLayout<Vertex>.stride * worldMesh.count,
        options: .storageModeShared)
    else {
      fatalError("Failed to allocate vertex buffer")
    }

    self.device = device
    self.commandQueue = commandQueue
    self.pipelineState = try! Renderer.makePipelineState(device: device)
    self.depthState = Renderer.makeDepthState(device: device)
    self.vertexBuffer = vertexBuffer
    self.uniformsBuffer = uniformsBuffer
    self.vertexCount = worldMesh.count

    resize(drawableSize: drawableSize)
  }

  public func resize(drawableSize: CGSize) {
    guard drawableSize.width > 0, drawableSize.height > 0 else {
      depthTexture = nil
      return
    }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .depth32Float,
      width: Int(drawableSize.width),
      height: Int(drawableSize.height),
      mipmapped: false)

    descriptor.usage = .renderTarget
    descriptor.storageMode = .private
    depthTexture = device.makeTexture(descriptor: descriptor)
  }

  public func render(into metalLayer: CAMetalLayer, camera: CameraState) {
    guard let drawable = metalLayer.nextDrawable(),
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let depthTexture
    else {
      return
    }

    let drawableSize = metalLayer.drawableSize
    let aspect = Float(drawableSize.width / drawableSize.height)
    guard aspect > 0 else {
      return
    }

    let projection = float4x4.perspective(
      fov: 65.0 * (.pi / 180.0),
      aspect: aspect,
      near: 0.1,
      far: 1000.0)

    let view =
      float4x4(rotationX: camera.pitch)
      * float4x4(rotationY: camera.yaw)
      * float4x4(translation: -camera.position)

    var uniforms = Uniforms(projection: projection, view: view)
    memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

    let passDescriptor = MTLRenderPassDescriptor()
    passDescriptor.colorAttachments[0].texture = drawable.texture
    passDescriptor.colorAttachments[0].loadAction = .clear
    passDescriptor.colorAttachments[0].storeAction = .store
    passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
      red: 0.6,
      green: 0.8,
      blue: 1.0,
      alpha: 1.0)

    passDescriptor.depthAttachment.texture = depthTexture
    passDescriptor.depthAttachment.loadAction = .clear
    passDescriptor.depthAttachment.storeAction = .dontCare
    passDescriptor.depthAttachment.clearDepth = 1.0

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
      return
    }

    encoder.setRenderPipelineState(pipelineState)
    encoder.setDepthStencilState(depthState)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    encoder.endEncoding()

    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private static func makePipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
    let library = try makeShaderLibrary(device: device)

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

    vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
    vertexDescriptor.layouts[0].stepFunction = .perVertex

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
    descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
    descriptor.vertexDescriptor = vertexDescriptor
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.depthAttachmentPixelFormat = .depth32Float

    return try device.makeRenderPipelineState(descriptor: descriptor)
  }

  private static func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
    guard let shaderURL = Bundle.module.url(forResource: "VoxelShaders", withExtension: "metallib")
    else {
      throw ShaderLibraryError.missingLibrary
    }

    return try device.makeLibrary(URL: shaderURL)
  }

  private static func makeDepthState(device: MTLDevice) -> MTLDepthStencilState {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true

    guard let depthState = device.makeDepthStencilState(descriptor: descriptor) else {
      fatalError("Failed to create depth stencil state")
    }

    return depthState
  }
}

enum ShaderLibraryError: Error {
  case missingLibrary
}
