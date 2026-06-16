import CoreGraphics
import Metal
import QuartzCore

// `Renderer` is the Metal-facing half of the demo.
//
// It does not own gameplay state. Instead it receives a camera snapshot each frame and draws
// the current world mesh using Metal pipeline/buffer objects prepared at startup.
public final class Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState
  private let projectionConfiguration: ProjectionConfiguration
  private let uniformsBuffer: MTLBuffer

  private var meshBuffers: MeshBuffers
  private var synchronizedMeshRevision: UInt64
  private var depthTexture: MTLTexture?

  public var currentVertexCount: Int {
    meshBuffers.vertexCount
  }

  public init(
    device: MTLDevice,
    world: VoxelWorld,
    drawableSize: CGSize,
    projectionConfiguration: ProjectionConfiguration = .default
  ) throws {
    guard let commandQueue = device.makeCommandQueue() else {
      throw RendererSetupError.commandQueueUnavailable
    }

    guard
      let uniformsBuffer = device.makeBuffer(
        length: MemoryLayout<Uniforms>.stride,
        options: .storageModeShared)
    else {
      throw RendererSetupError.uniformsBufferUnavailable
    }

    let shaderLibrary: ShaderLibrary
    do {
      shaderLibrary = try ShaderLibrary(device: device)
    } catch {
      throw RendererSetupError.shaderLibraryUnavailable(error)
    }

    self.device = device
    self.commandQueue = commandQueue
    self.pipelineState = try RenderPipelineFactory.makePipelineState(
      device: device,
      library: shaderLibrary.library)
    self.depthState = try RenderPipelineFactory.makeDepthState(device: device)
    self.projectionConfiguration = projectionConfiguration
    self.meshBuffers = try MeshBuffers(device: device, mesh: world.makeWorldMesh())
    self.synchronizedMeshRevision = world.meshRevision
    self.uniformsBuffer = uniformsBuffer

    resize(drawableSize: drawableSize)
  }

  // The depth texture must always match the drawable size because depth testing happens
  // pixel-for-pixel alongside the color target.
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

  // Before drawing, the renderer checks whether the voxel grid changed. If it did, a fresh
  // mesh is generated and uploaded to the GPU so the picture matches the current world.
  public func render(into metalLayer: CAMetalLayer, world: VoxelWorld, camera: CameraState) throws {
    try synchronizeWorldMeshIfNeeded(with: world)

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

    // Update the per-frame camera matrices that the vertex shader reads.
    var uniforms = CameraUniforms(
      camera: camera,
      projectionConfiguration: projectionConfiguration,
      drawableSize: drawableSize
    ).rawValue
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

  private func synchronizeWorldMeshIfNeeded(with world: VoxelWorld) throws {
    guard synchronizedMeshRevision != world.meshRevision else {
      return
    }

    meshBuffers = try MeshBuffers(device: device, mesh: world.makeWorldMesh())
    synchronizedMeshRevision = world.meshRevision
  }
}
