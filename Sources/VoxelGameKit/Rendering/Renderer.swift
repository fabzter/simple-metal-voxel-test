import CoreGraphics
import Metal
import QuartzCore
import simd

// `Renderer` is the Metal-facing half of the demo.
//
// It does not own gameplay state. Instead it receives a camera snapshot and a selected hit each
// frame, then draws only the currently visible chunk meshes plus a face highlight for the target.
public final class Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let highlightPipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState
  private let projectionConfiguration: ProjectionConfiguration
  private let uniformsBuffer: MTLBuffer
  private let materialAtlas: MaterialAtlas

  private var chunkMeshBuffers: [VoxelChunkIndex: MeshBuffers]
  private var synchronizedChunkRevisions: [VoxelChunkIndex: UInt64]
  private var selectionBuffer: MTLBuffer?
  private var selectedHit: VoxelRaycastHit?
  private var depthTexture: MTLTexture?

  public var materialDebugMode: MaterialDebugMode = .hybrid
  public private(set) var currentVisibleChunkCount: Int = 0

  public var currentVertexCount: Int {
    chunkMeshBuffers.values.reduce(0) { $0 + $1.vertexCount }
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
    self.highlightPipelineState = try RenderPipelineFactory.makeHighlightPipelineState(
      device: device,
      library: shaderLibrary.library)
    self.depthState = try RenderPipelineFactory.makeDepthState(device: device)
    self.projectionConfiguration = projectionConfiguration
    self.uniformsBuffer = uniformsBuffer
    self.materialAtlas = try MaterialAtlas(device: device)
    self.chunkMeshBuffers = [:]
    self.synchronizedChunkRevisions = [:]

    try rebuildAllChunks(for: world)
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

  public func render(
    into metalLayer: CAMetalLayer,
    world: VoxelWorld,
    camera: CameraState,
    selectedHit: VoxelRaycastHit?
  ) throws {
    try synchronizeWorldMeshIfNeeded(with: world)
    try synchronizeSelectionBuffer(for: selectedHit)

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

    let cameraUniforms = CameraUniforms(
      camera: camera,
      projectionConfiguration: projectionConfiguration,
      drawableSize: drawableSize)
    var uniforms = cameraUniforms.rawValue(materialDebugMode: materialDebugMode)
    memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

    let frustumCuller = FrustumCuller(
      viewProjectionMatrix: simd_mul(cameraUniforms.projection, cameraUniforms.view))

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
    encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
    encoder.setFragmentTexture(materialAtlas.texture, index: 0)

    var visibleChunkCount = 0
    for chunkIndex in world.allChunkIndices() {
      guard let meshBuffers = chunkMeshBuffers[chunkIndex], meshBuffers.vertexCount > 0 else {
        continue
      }

      let bounds = ChunkBounds.bounds(for: chunkIndex, chunkSize: world.chunkSize)
      guard frustumCuller.isVisible(bounds: bounds) else {
        continue
      }

      visibleChunkCount += 1
      encoder.setVertexBuffer(meshBuffers.vertexBuffer, offset: 0, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshBuffers.vertexCount)
    }
    currentVisibleChunkCount = visibleChunkCount

    if let selectionBuffer {
      encoder.setRenderPipelineState(highlightPipelineState)
      encoder.setVertexBuffer(selectionBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
      encoder.drawPrimitives(
        type: .line,
        vertexStart: 0,
        vertexCount: selectionBuffer.length / MemoryLayout<SIMD3<Float>>.stride)
    }

    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func rebuildAllChunks(for world: VoxelWorld) throws {
    chunkMeshBuffers.removeAll(keepingCapacity: true)
    synchronizedChunkRevisions.removeAll(keepingCapacity: true)

    for chunkIndex in world.allChunkIndices() {
      let mesh = world.makeWorldMesh(for: chunkIndex)
      chunkMeshBuffers[chunkIndex] = try MeshBuffers(device: device, mesh: mesh)
      synchronizedChunkRevisions[chunkIndex] = world.chunkRevision(for: chunkIndex)
    }
  }

  private func synchronizeWorldMeshIfNeeded(with world: VoxelWorld) throws {
    for chunkIndex in world.allChunkIndices() {
      let latestRevision = world.chunkRevision(for: chunkIndex)
      guard synchronizedChunkRevisions[chunkIndex] != latestRevision else {
        continue
      }

      chunkMeshBuffers[chunkIndex] = try MeshBuffers(
        device: device, mesh: world.makeWorldMesh(for: chunkIndex))
      synchronizedChunkRevisions[chunkIndex] = latestRevision
    }
  }

  private func synchronizeSelectionBuffer(for selectedHit: VoxelRaycastHit?) throws {
    let changedSelection =
      selectedHit?.solidCell != self.selectedHit?.solidCell
      || selectedHit?.face?.label != self.selectedHit?.face?.label
    guard changedSelection else {
      return
    }

    self.selectedHit = selectedHit

    guard let selectedHit, let face = selectedHit.face else {
      selectionBuffer = nil
      return
    }

    let vertices = SelectionHighlightMesh(cell: selectedHit.solidCell, face: face).vertices
    guard
      let buffer = device.makeBuffer(
        bytes: vertices,
        length: MemoryLayout<SIMD3<Float>>.stride * vertices.count,
        options: .storageModeShared)
    else {
      throw RendererSetupError.highlightBufferUnavailable
    }

    selectionBuffer = buffer
  }
}
