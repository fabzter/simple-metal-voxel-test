import CoreGraphics
import Metal
import QuartzCore
import simd

public final class Renderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let highlightPipelineState: MTLRenderPipelineState
  private let depthState: MTLDepthStencilState
  private let projectionConfiguration: ProjectionConfiguration
  private let lodConfiguration: LODConfiguration
  private let uniformsBuffer: MTLBuffer
  private let materialAtlas: MaterialAtlas
  private let occlusionCuller = ChunkOcclusionCuller()

  private var meshBufferCache: [ChunkLODKey: MeshBuffers]
  private var synchronizedChunkRevisions: [VoxelChunkIndex: UInt64]
  private var selectionBuffer: MTLBuffer?
  private var overlayHit: VoxelRaycastHit?
  private var depthTexture: MTLTexture?

  public var debugSettings = RenderDebugSettings()
  public private(set) var currentVisibleChunkCount: Int = 0
  public private(set) var currentLODCounts: [Int: Int] = [:]

  public var currentVertexCount: Int {
    meshBufferCache.values.reduce(0) { $0 + $1.vertexCount }
  }

  public init(
    device: MTLDevice,
    world: VoxelWorld,
    drawableSize: CGSize,
    projectionConfiguration: ProjectionConfiguration = .default,
    lodConfiguration: LODConfiguration = .default
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
    self.lodConfiguration = lodConfiguration
    self.uniformsBuffer = uniformsBuffer
    self.materialAtlas = try MaterialAtlas(device: device)
    self.meshBufferCache = [:]
    self.synchronizedChunkRevisions = Dictionary(
      uniqueKeysWithValues: world.allChunkIndices().map { ($0, world.chunkRevision(for: $0)) })

    resize(drawableSize: drawableSize)
  }

  public var materialDebugMode: MaterialDebugMode {
    get { debugSettings.materialMode }
    set { debugSettings.materialMode = newValue }
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
    selectedHit: VoxelRaycastHit?,
    editFeedback: EditFeedback?
  ) throws {
    synchronizeWorldMeshRevisions(with: world)
    let activeOverlayHit = editFeedback?.hit ?? selectedHit
    try synchronizeSelectionBuffer(for: activeOverlayHit)

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

    let highlightColor = makeHighlightColor(editFeedback: editFeedback)
    let cameraUniforms = CameraUniforms(
      camera: camera,
      projectionConfiguration: projectionConfiguration,
      drawableSize: drawableSize)

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
    encoder.setFragmentTexture(materialAtlas.texture, index: 0)

    let cameraChunk = world.chunkIndex(
      containing: VoxelIndex(
        x: Int(floor(camera.position.x + 0.5)),
        y: Int(floor(camera.position.y + 0.5)),
        z: Int(floor(camera.position.z + 0.5))))

    var visibleChunkCount = 0
    var lodCounts: [Int: Int] = [:]

    for chunkIndex in world.allChunkIndices() {
      guard let lodLevel = selectedLODLevel(for: chunkIndex, cameraChunk: cameraChunk) else {
        continue
      }

      let bounds = ChunkBounds.bounds(for: chunkIndex, chunkSize: world.chunkSize)
      if debugSettings.frustumCullingEnabled && !frustumCuller.isVisible(bounds: bounds) {
        continue
      }
      if debugSettings.occlusionCullingEnabled
        && !occlusionCuller.isVisible(chunkIndex: chunkIndex, world: world, camera: camera)
      {
        continue
      }

      let meshBuffers = try meshBuffer(for: chunkIndex, lodLevel: lodLevel, world: world)
      guard meshBuffers.vertexCount > 0 else { continue }

      visibleChunkCount += 1
      lodCounts[lodLevel, default: 0] += 1

      var uniforms = cameraUniforms.rawValue(
        materialDebugMode: debugSettings.materialMode,
        lodTintOverlayMode: debugSettings.lodTintOverlayMode,
        lodTintColor: lodTintColor(for: lodLevel),
        highlightColor: highlightColor)
      memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

      encoder.setVertexBuffer(meshBuffers.vertexBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
      encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 1)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshBuffers.vertexCount)
    }
    currentVisibleChunkCount = visibleChunkCount
    currentLODCounts = lodCounts

    if let selectionBuffer {
      var uniforms = cameraUniforms.rawValue(
        materialDebugMode: debugSettings.materialMode,
        lodTintOverlayMode: .off,
        lodTintColor: SIMD4<Float>(0, 0, 0, 0),
        highlightColor: highlightColor)
      memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

      encoder.setRenderPipelineState(highlightPipelineState)
      encoder.setVertexBuffer(selectionBuffer, offset: 0, index: 0)
      encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
      encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 1)
      encoder.drawPrimitives(
        type: .line,
        vertexStart: 0,
        vertexCount: selectionBuffer.length / MemoryLayout<SIMD3<Float>>.stride)
    }

    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func meshBuffer(for chunkIndex: VoxelChunkIndex, lodLevel: Int, world: VoxelWorld)
    throws -> MeshBuffers
  {
    let key = ChunkLODKey(chunkIndex: chunkIndex, lodLevel: lodLevel)
    if let cached = meshBufferCache[key] {
      return cached
    }

    let voxelStride = debugSettings.lodEnabled ? lodConfiguration.levels[lodLevel].voxelStride : 1
    let mesh = world.makeWorldMesh(for: chunkIndex, voxelStride: voxelStride)
    let buffer = try MeshBuffers(device: device, mesh: mesh)
    meshBufferCache[key] = buffer
    return buffer
  }

  private func selectedLODLevel(for chunkIndex: VoxelChunkIndex, cameraChunk: VoxelChunkIndex?)
    -> Int?
  {
    guard let cameraChunk else { return 0 }
    let distance = max(
      abs(chunkIndex.x - cameraChunk.x),
      abs(chunkIndex.y - cameraChunk.y),
      abs(chunkIndex.z - cameraChunk.z)
    )

    if !debugSettings.lodEnabled {
      return distance <= lodConfiguration.levels.last?.maxChunkDistance ?? 0 ? 0 : nil
    }

    for (index, level) in lodConfiguration.levels.enumerated()
    where distance <= level.maxChunkDistance {
      return index
    }
    return nil
  }

  private func synchronizeWorldMeshRevisions(with world: VoxelWorld) {
    for chunkIndex in world.allChunkIndices() {
      let latestRevision = world.chunkRevision(for: chunkIndex)
      guard synchronizedChunkRevisions[chunkIndex] != latestRevision else {
        continue
      }

      meshBufferCache = meshBufferCache.filter { $0.key.chunkIndex != chunkIndex }
      synchronizedChunkRevisions[chunkIndex] = latestRevision
    }
  }

  private func synchronizeSelectionBuffer(for overlayHit: VoxelRaycastHit?) throws {
    let changedSelection =
      overlayHit?.solidCell != self.overlayHit?.solidCell
      || overlayHit?.face?.label != self.overlayHit?.face?.label
    guard changedSelection else {
      return
    }

    self.overlayHit = overlayHit

    guard let overlayHit, let face = overlayHit.face else {
      selectionBuffer = nil
      return
    }

    let vertices = SelectionHighlightMesh(cell: overlayHit.solidCell, face: face).vertices
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

  private func lodTintColor(for lodLevel: Int) -> SIMD4<Float> {
    guard debugSettings.lodTintOverlayMode != .off else {
      return SIMD4<Float>(0, 0, 0, 0)
    }

    switch lodLevel {
    case 0:
      return SIMD4<Float>(0.15, 0.55, 1.0, 0.12)
    case 1:
      return SIMD4<Float>(1.0, 0.78, 0.12, 0.18)
    default:
      return SIMD4<Float>(1.0, 0.35, 0.18, 0.24)
    }
  }

  private func makeHighlightColor(editFeedback: EditFeedback?) -> SIMD4<Float> {
    guard let editFeedback else {
      return SIMD4<Float>(1.0, 0.9, 0.2, 1.0)
    }

    let pulse = 0.65 + 0.35 * sin((0.18 - editFeedback.remainingTime) * 36.0)
    switch editFeedback.kind {
    case .remove:
      return SIMD4<Float>(1.0 * pulse, 0.35, 0.25, 1.0)
    case .place:
      return SIMD4<Float>(0.35, 1.0 * pulse, 0.35, 1.0)
    }
  }
}
