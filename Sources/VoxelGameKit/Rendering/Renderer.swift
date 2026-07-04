import CoreGraphics
import Metal
import QuartzCore
import simd

public final class Renderer {
 private struct VisibleChunkDraw {
  let meshBuffers: MeshBuffers
  let lodLevel: Int
  var fadeThreshold: Float = 1.0  // 1.0 = fully opaque; <1.0 = dither threshold
 }

 /// Holds the old mesh for a chunk whose LOD just changed, so it can dither out
 /// while the new mesh dithers in over a short fade duration.
 private struct MeshFade {
  let oldBuffers: MeshBuffers
  let lodLevel: Int
  let startTime: Double
 }

 private struct VisibleChunkSelection {
  let chunkIndex: VoxelChunkIndex
  let lodLevel: Int
 }

 private let device: MTLDevice
 private let commandQueue: MTLCommandQueue
 private let pipelineState: MTLRenderPipelineState
 private let highlightPipelineState: MTLRenderPipelineState
 private let depthState: MTLDepthStencilState
 public var projectionConfiguration: ProjectionConfiguration
 private let lodConfiguration: LODConfiguration
 private let materialAtlas: MaterialAtlas
 private let occlusionCuller = ChunkOcclusionCuller()
 private let emptyMeshBuffers: MeshBuffers

 private var meshBufferCache: [ChunkLODKey: MeshBuffers]
 private var latestChunkKeys: [VoxelChunkIndex: ChunkLODKey] = [:]
 private var fadingChunks: [VoxelChunkIndex: MeshFade] = [:]
 private var synchronizedChunkRevisions: [VoxelChunkIndex: UInt64]
 private var lastChunkLODLevels: [VoxelChunkIndex: Int]
 private var selectionBuffer: MTLBuffer?
 private var overlayHit: VoxelRaycastHit?

 // Injectible clock so tests can fast-forward fade expiry without wall-clock waits.
 private let fadeDuration: Double = 0.25
 private let maxSimultaneousFades = 128
 var timeSource: () -> Double = { CACurrentMediaTime() }
 private var depthTexture: MTLTexture?

 public var debugSettings = RenderDebugSettings()
 public private(set) var currentVisibleChunkCount: Int = 0
 public private(set) var currentLODCounts: [Int: Int] = [:]

 public var currentVertexCount: Int {
  meshBufferCache.values.reduce(0) { $0 + $1.vertexCount }
 }

 // MARK: Test hooks — internal for @testable import; invisible to app code.

 var meshBufferCacheCount: Int { meshBufferCache.count }

 func cachedLODKeys(for chunkIndex: VoxelChunkIndex) -> [ChunkLODKey] {
  meshBufferCache.keys.filter { $0.chunkIndex == chunkIndex }
 }

 func cachedBuffersAreAllIdentical() -> Bool {
  let buffers = meshBufferCache.values.map { $0.vertexBuffer }
  guard let first = buffers.first else { return true }
  return buffers.allSatisfy { $0 === first }
 }

 var activeFadeCount: Int { fadingChunks.count }

 func isFading(_ chunkIndex: VoxelChunkIndex) -> Bool { fadingChunks[chunkIndex] != nil }

 public init(
  device: MTLDevice,
  world: VoxelWorld,
  drawableSize: CGSize,
  projectionConfiguration: ProjectionConfiguration = .default,
  lodConfiguration: LODConfiguration = .default
 ) throws {
  if let error = lodConfiguration.validateStrideChain() {
   throw RendererSetupError.invalidLODConfiguration(error)
  }
  guard let commandQueue = device.makeCommandQueue() else {
   throw RendererSetupError.commandQueueUnavailable
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
  self.materialAtlas = try MaterialAtlas(device: device, commandQueue: commandQueue)
  self.emptyMeshBuffers = try MeshBuffers(device: device, mesh: WorldMesh(vertices: []))
  self.meshBufferCache = [:]
  self.synchronizedChunkRevisions = Dictionary(
   uniqueKeysWithValues: world.allChunkIndices().map { ($0, world.chunkRevision(for: $0)) })
  self.lastChunkLODLevels = [:]

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

 /// Resets all local caches and rebuilds the revision map for a fresh or restored world.
 /// After calling this, the next render repopulates the mesh cache from the new world.
 public func resetWorldSynchronization(with world: VoxelWorld) {
  meshBufferCache.removeAll()
  latestChunkKeys.removeAll()
  fadingChunks.removeAll()
  lastChunkLODLevels.removeAll()
  synchronizedChunkRevisions = Dictionary(
   uniqueKeysWithValues: world.allChunkIndices().map { ($0, world.chunkRevision(for: $0)) })
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

  let drawableSize = metalLayer.drawableSize
  guard drawableSize.width > 0, drawableSize.height > 0, let depthTexture else {
   return
  }

  let highlightColor = makeHighlightColor(editFeedback: editFeedback)
  let cameraUniforms = CameraUniforms(
   camera: camera,
   projectionConfiguration: projectionConfiguration,
   drawableSize: drawableSize)

  let frustumCuller = FrustumCuller(
   viewProjectionMatrix: simd_mul(cameraUniforms.projection, cameraUniforms.view))

  var visibleLODLevels: [VoxelChunkIndex: Int] = [:]
  var visibleSelections: [VisibleChunkSelection] = []
  visibleSelections.reserveCapacity(world.allChunkIndices().count)

  for chunkIndex in world.allChunkIndices() {
   guard
    let lodLevel = selectedLODLevel(
     for: chunkIndex,
     cameraPosition: camera.position,
     chunkSize: world.chunkSize)
   else {
    continue
   }

   let bounds = ChunkBounds.bounds(for: chunkIndex, chunkSize: world.chunkSize)
   if debugSettings.frustumCullingEnabled && !frustumCuller.isVisible(bounds: bounds) {
    continue
   }
   if debugSettings.occlusionCullingEnabled
    && debugSettings.lodTintOverlayMode == .off
    && !occlusionCuller.isVisible(chunkIndex: chunkIndex, world: world, camera: camera)
   {
    continue
   }

   visibleLODLevels[chunkIndex] = lodLevel
   visibleSelections.append(VisibleChunkSelection(chunkIndex: chunkIndex, lodLevel: lodLevel))
  }

  var visibleChunkCount = 0
  var lodCounts: [Int: Int] = [:]
  var visibleDraws: [VisibleChunkDraw] = []
  visibleDraws.reserveCapacity(visibleSelections.count)

  let now = timeSource()

  for selection in visibleSelections {
   let seamConfiguration = makeSeamConfiguration(
    for: selection.chunkIndex,
    lodLevel: selection.lodLevel,
    visibleLODLevels: visibleLODLevels)
   let meshBuffers = try meshBuffer(
    for: selection.chunkIndex,
    lodLevel: selection.lodLevel,
    seamConfiguration: seamConfiguration,
    world: world)
   guard meshBuffers.vertexCount > 0 else { continue }

   visibleChunkCount += 1
   lodCounts[selection.lodLevel, default: 0] += 1
   let progress = fadeProgress(for: selection.chunkIndex, now: now)
   var draw = VisibleChunkDraw(meshBuffers: meshBuffers, lodLevel: selection.lodLevel)
   if let progress { draw.fadeThreshold = min(progress, 1) }  // new mesh dithers IN
   visibleDraws.append(draw)
  }

  // When a chunk's LOD changed this frame, also draw the OLD mesh so it dithers OUT.
  // The new (dither-in) and old (dither-out) meshes interleave per pixel via Bayer
  // screen-door dither for the fade duration, then the old entry expires.
  var expiredFades: [VoxelChunkIndex] = []
  for (chunkIndex, fade) in fadingChunks {
   let progress = Float((now - fade.startTime) / fadeDuration)
   if progress >= 1 {
    expiredFades.append(chunkIndex)
    continue
   }
   guard visibleLODLevels[chunkIndex] != nil else { continue }
   visibleDraws.append(
    VisibleChunkDraw(
     meshBuffers: fade.oldBuffers, lodLevel: fade.lodLevel, fadeThreshold: 1 - progress))
  }
  for chunkIndex in expiredFades { fadingChunks.removeValue(forKey: chunkIndex) }

  currentVisibleChunkCount = visibleChunkCount
  currentLODCounts = lodCounts

  // Apple recommends acquiring CAMetalLayer drawables as late as possible. We therefore finish
  // the CPU-side visibility walk and mesh cache lookups before touching the limited drawable
  // pool for the frame.
  guard let commandBuffer = commandQueue.makeCommandBuffer(),
   let drawable = metalLayer.nextDrawable()
  else {
   return
  }

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
  encoder.setFrontFacing(.counterClockwise)
  encoder.setCullMode(.back)
  encoder.setFragmentTexture(materialAtlas.texture, index: 0)

  for draw in visibleDraws {
   var uniforms = cameraUniforms.rawValue(
    materialDebugMode: debugSettings.materialMode,
    lodTintOverlayMode: debugSettings.lodTintOverlayMode,
    lodTintColor: lodTintColor(for: draw.lodLevel),
    highlightColor: highlightColor,
    fadeThreshold: draw.fadeThreshold)

   encoder.setVertexBuffer(draw.meshBuffers.vertexBuffer, offset: 0, index: 0)
   encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
   encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
   encoder.drawPrimitives(
    type: .triangle,
    vertexStart: 0,
    vertexCount: draw.meshBuffers.vertexCount)
  }

  if let selectionBuffer {
   var uniforms = cameraUniforms.rawValue(
    materialDebugMode: debugSettings.materialMode,
    lodTintOverlayMode: .off,
    lodTintColor: SIMD4<Float>(0, 0, 0, 0),
    highlightColor: highlightColor,
    fadeThreshold: 1.0)

   encoder.setRenderPipelineState(highlightPipelineState)
   encoder.setVertexBuffer(selectionBuffer, offset: 0, index: 0)
   encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
   encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
   encoder.drawPrimitives(
    type: .line,
    vertexStart: 0,
    vertexCount: selectionBuffer.length / MemoryLayout<SIMD3<Float>>.stride)
  }

  encoder.endEncoding()
  commandBuffer.present(drawable)
  commandBuffer.commit()
 }

 private func meshBuffer(
  for chunkIndex: VoxelChunkIndex,
  lodLevel: Int,
  seamConfiguration: ChunkSeamConfiguration,
  world: VoxelWorld
 )
  throws -> MeshBuffers
 {
  let key = ChunkLODKey(
   chunkIndex: chunkIndex,
   lodLevel: lodLevel,
   seamConfiguration: seamConfiguration)

  if let cached = meshBufferCache[key] {
   return cached
  }

  // A chunk is drawn with exactly one (LOD, seam) combination per frame. Keeping only
  // the most recent mesh per chunk stops the cache growing as LOD rings sweep the world
  // while the player moves. The rare cost is a sub-millisecond re-mesh when a chunk
  // crosses back over a ring boundary (already damped by LOD hysteresis).
  if let previousKey = latestChunkKeys[chunkIndex], previousKey != key {
   // Before discarding the previous LOD variant, capture it so we can dither it
   // out over a short fade while the new mesh dithers in.
   if let oldBuffers = meshBufferCache[previousKey],
    oldBuffers.vertexCount > 0,
    fadingChunks.count < maxSimultaneousFades
   {
    fadingChunks[chunkIndex] = MeshFade(
     oldBuffers: oldBuffers, lodLevel: previousKey.lodLevel, startTime: timeSource())
   }
   meshBufferCache.removeValue(forKey: previousKey)
  }

  let voxelStride = debugSettings.lodEnabled ? lodConfiguration.levels[lodLevel].voxelStride : 1
  let mesh = world.makeWorldMesh(
   for: chunkIndex,
   voxelStride: voxelStride,
   seamConfiguration: seamConfiguration)
  // All-air chunks (most of the sky) produce zero vertices. Give them all the same
  // shared sentinel instead of one Metal allocation each — the draw loop already skips
  // vertexCount == 0, so the sentinel buffer is never bound.
  let buffer =
   mesh.vertexCount == 0
   ? emptyMeshBuffers
   : try MeshBuffers(device: device, mesh: mesh)
  meshBufferCache[key] = buffer
  latestChunkKeys[chunkIndex] = key
  return buffer
 }

 private func makeSeamConfiguration(
  for chunkIndex: VoxelChunkIndex,
  lodLevel: Int,
  visibleLODLevels: [VoxelChunkIndex: Int]
 ) -> ChunkSeamConfiguration {
  guard debugSettings.lodEnabled else {
   return .none
  }

  let voxelStride = lodConfiguration.levels[lodLevel].voxelStride
  let maxComponent = chunkComponentCount() - 1
  var configuration = ChunkSeamConfiguration.none

  func finerNeighborStride(at neighbor: VoxelChunkIndex) -> Int? {
   guard let neighborLODLevel = visibleLODLevels[neighbor] else {
    return nil
   }
   let neighborStride = lodConfiguration.levels[neighborLODLevel].voxelStride
   guard neighborStride < voxelStride else {
    return nil
   }
   return neighborStride
  }

  let positiveX = VoxelChunkIndex(x: chunkIndex.x + 1, y: chunkIndex.y, z: chunkIndex.z)
  let negativeX = VoxelChunkIndex(x: chunkIndex.x - 1, y: chunkIndex.y, z: chunkIndex.z)
  let positiveY = VoxelChunkIndex(x: chunkIndex.x, y: chunkIndex.y + 1, z: chunkIndex.z)
  let negativeY = VoxelChunkIndex(x: chunkIndex.x, y: chunkIndex.y - 1, z: chunkIndex.z)
  let positiveZ = VoxelChunkIndex(x: chunkIndex.x, y: chunkIndex.y, z: chunkIndex.z + 1)
  let negativeZ = VoxelChunkIndex(x: chunkIndex.x, y: chunkIndex.y, z: chunkIndex.z - 1)

  if chunkIndex.x + 1 < maxComponent {
   configuration.positiveXFinerStride = finerNeighborStride(at: positiveX)
  }
  if chunkIndex.x > 0 {
   configuration.negativeXFinerStride = finerNeighborStride(at: negativeX)
  }
  if chunkIndex.y + 1 < maxComponent {
   configuration.positiveYFinerStride = finerNeighborStride(at: positiveY)
  }
  if chunkIndex.y > 0 {
   configuration.negativeYFinerStride = finerNeighborStride(at: negativeY)
  }
  if chunkIndex.z + 1 < maxComponent {
   configuration.positiveZFinerStride = finerNeighborStride(at: positiveZ)
  }
  if chunkIndex.z > 0 {
   configuration.negativeZFinerStride = finerNeighborStride(at: negativeZ)
  }

  return configuration
 }

 private func chunkComponentCount() -> Int {
  let chunkCount = synchronizedChunkRevisions.keys.reduce(into: SIMD3<Int>(repeating: 0)) {
   partialResult, chunkIndex in
   partialResult.x = max(partialResult.x, chunkIndex.x + 1)
   partialResult.y = max(partialResult.y, chunkIndex.y + 1)
   partialResult.z = max(partialResult.z, chunkIndex.z + 1)
  }
  return max(chunkCount.x, max(chunkCount.y, chunkCount.z))
 }

 // Selects an LOD level for a chunk using world-space distance from the camera to the chunk
 // center, plus hysteresis to prevent chunks from rapidly flipping between levels when the
 // camera is near a boundary.
 private func selectedLODLevel(
  for chunkIndex: VoxelChunkIndex,
  cameraPosition: SIMD3<Float>,
  chunkSize: Int
 ) -> Int? {
  // An empty public configuration should fail safe to "render full detail" instead of making
  // the entire world disappear.
  guard !lodConfiguration.levels.isEmpty else {
   lastChunkLODLevels[chunkIndex] = 0
   return 0
  }

  let chunkCenter = SIMD3<Float>(
   Float(chunkIndex.x * chunkSize + chunkSize / 2),
   Float(chunkIndex.y * chunkSize + chunkSize / 2),
   Float(chunkIndex.z * chunkSize + chunkSize / 2))

  let distance = simd_length(chunkCenter - cameraPosition)
  let worldHysteresis = Float(chunkSize) * 1.0

  if !debugSettings.lodEnabled {
   let maxDistance =
    Float(lodConfiguration.levels.last?.maxChunkDistance ?? 0) * Float(chunkSize)
   return distance <= maxDistance ? 0 : nil
  }

  let previousLevel = lastChunkLODLevels[chunkIndex]

  for (index, level) in lodConfiguration.levels.enumerated() {
   let threshold = Float(level.maxChunkDistance) * Float(chunkSize)

   // Apply hysteresis: if this chunk was already at this level, require the camera to
   // move past the threshold plus a margin before downgrading to a coarser level.
   let effectiveThreshold: Float
   if let previousLevel, previousLevel == index, index < lodConfiguration.levels.count - 1 {
    effectiveThreshold = threshold + worldHysteresis
   } else {
    effectiveThreshold = threshold
   }

   if distance <= effectiveThreshold {
    lastChunkLODLevels[chunkIndex] = index
    return index
   }
  }

  lastChunkLODLevels[chunkIndex] = nil
  return nil
 }

 private func synchronizeWorldMeshRevisions(with world: VoxelWorld) {
  for chunkIndex in world.allChunkIndices() {
   let latestRevision = world.chunkRevision(for: chunkIndex)
   guard synchronizedChunkRevisions[chunkIndex] != latestRevision else {
    continue
   }

   meshBufferCache = meshBufferCache.filter { $0.key.chunkIndex != chunkIndex }
   latestChunkKeys.removeValue(forKey: chunkIndex)
   fadingChunks.removeValue(forKey: chunkIndex)
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
   return SIMD4<Float>(0, 0, 0, 0)
  case 1:
   return SIMD4<Float>(1.0, 0.80, 0.15, 0.30)
  default:
   return SIMD4<Float>(1.0, 0.25, 0.20, 0.30)
  }
 }

 private func fadeProgress(for chunkIndex: VoxelChunkIndex, now: Double) -> Float? {
  guard let fade = fadingChunks[chunkIndex] else { return nil }
  return Float((now - fade.startTime) / fadeDuration)
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
