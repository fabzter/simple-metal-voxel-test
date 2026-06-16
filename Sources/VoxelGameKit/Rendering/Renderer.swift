import CoreGraphics
import Metal
import QuartzCore

public final class Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState
  private let meshBuffers: MeshBuffers
  private let uniformsBuffer: MTLBuffer

  private var depthTexture: MTLTexture?

  public init(device: MTLDevice, world: VoxelWorld, drawableSize: CGSize) {
    guard let commandQueue = device.makeCommandQueue() else {
      fatalError("Failed to create command queue")
    }

    guard
      let uniformsBuffer = device.makeBuffer(
        length: MemoryLayout<Uniforms>.stride,
        options: .storageModeShared)
    else {
      fatalError("Failed to allocate uniforms buffer")
    }

    let shaderLibrary = try! ShaderLibrary(device: device)

    self.device = device
    self.commandQueue = commandQueue
    self.pipelineState = try! RenderPipelineFactory.makePipelineState(
      device: device,
      library: shaderLibrary.library)
    self.depthState = RenderPipelineFactory.makeDepthState(device: device)
    self.meshBuffers = MeshBuffers(device: device, mesh: world.makeWorldMesh())
    self.uniformsBuffer = uniformsBuffer

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
    guard drawableSize.width > 0, drawableSize.height > 0 else {
      return
    }

    var uniforms = CameraUniforms(camera: camera, drawableSize: drawableSize).rawValue
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
    encoder.setVertexBuffer(meshBuffers.vertexBuffer, offset: 0, index: 0)
    encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshBuffers.vertexCount)
    encoder.endEncoding()

    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}
