import Cocoa
import CoreGraphics
import Metal
import QuartzCore
import UniformTypeIdentifiers
import VoxelEngine

@MainActor
final class MetalView: NSView {
 private var scene: GameScene
 private let inputController: GameInputController
 private let device: MTLDevice
 private let renderer: Renderer
 private let debugHUDView: DebugHUDView
 private let minimapView: MinimapView
 private let crosshairView: CrosshairView
 private let helpOverlayView: HelpOverlayView
 private let debugControlPanelView: DebugControlPanelView
 private let statusBannerView: StatusBannerView
 private let hotbarView: HotbarView
 private var settings: SettingsStore
 private var renderScale: CGFloat

 private var gameLoop: GameLoop?
 private weak var observedWindow: NSWindow?
 private var hasPresentedRuntimeError = false
 private var isDebugPanelModeEnabled = false
 private var isHelpVisible = true
 private var isHUDVisible = true
 private var isMinimapVisible = true
 private var isCrosshairVisible = true
 private var isMouseCaptured = false
 private var hasShownWelcomeHint = false
 private let launchedFromSave: Bool
 private let soundEngine = GameSoundEngine()
 // Locomotion audio state: footsteps fire every fixed distance walked; a landing thud
 // fires when the player touches down after falling.
 private var footstepDistanceAccumulator: Float = 0
 private var wasGroundedLastFrame = true
 private var previousVerticalVelocity: Float = 0

 private var metalLayer: CAMetalLayer {
  guard let layer = layer as? CAMetalLayer else {
   fatalError("Expected CAMetalLayer backing")
  }
  return layer
 }

 static func make(
  frame: NSRect,
  deviceProvider: () -> MTLDevice? = MTLCreateSystemDefaultDevice
 ) throws -> MetalView {
  guard let device = deviceProvider() else {
   throw MetalViewError.metalUnavailable
  }

  // Attempt to restore a saved world; fall back to generating a fresh one.
  let scene: GameScene
  let launchedFromSave: Bool
  if let saveData = try? Data(contentsOf: Self.worldSaveURL),
   let state = WorldSaveCodec.decode(saveData),
   let restoredScene = sceneFromSaveState(state)
  {
   scene = restoredScene
   launchedFromSave = true
  } else {
   // Save file missing, corrupt, or incompatible — generate a fresh world.
   scene = GameScene(gridSize: 256)
   launchedFromSave = false
  }
  let settings = SettingsStore()
  let inputController = GameInputController()
  let drawableSize = makeDrawableSize(
   for: frame,
   backingScaleFactor: nil,
   renderScale: CGFloat(settings.renderScale))
  let renderer = try Renderer(device: device, world: scene.world, drawableSize: drawableSize)

  // The engine ships a good default sky; the demo picks its own slightly warmer mood to
  // show how a game customizes the engine's atmosphere.
  renderer.sky = SkyConfiguration(
   sunDirection: SIMD3<Float>(0.35, 0.78, 0.52),
   sunColor: SIMD3<Float>(1.0, 0.95, 0.84),
   zenithColor: SIMD3<Float>(0.28, 0.50, 0.92),
   horizonColor: SIMD3<Float>(0.78, 0.85, 0.93),
   groundColor: SIMD3<Float>(0.32, 0.29, 0.25),
   fogDensity: 0.004)

  let debugHUDView = DebugHUDView(frame: .zero)
  let minimapView = MinimapView(frame: .zero)
  let crosshairView = CrosshairView(frame: .zero)
  let helpOverlayView = HelpOverlayView(frame: .zero)
  let debugControlPanelView = DebugControlPanelView(frame: .zero)
  let statusBannerView = StatusBannerView(frame: .zero)
  let hotbarView = HotbarView(frame: .zero)

  let view = MetalView(
   configuredFrame: frame,
   scene: scene,
   inputController: inputController,
   device: device,
   renderer: renderer,
   debugHUDView: debugHUDView,
   minimapView: minimapView,
   crosshairView: crosshairView,
   helpOverlayView: helpOverlayView,
   debugControlPanelView: debugControlPanelView,
   statusBannerView: statusBannerView,
   hotbarView: hotbarView,
   settings: settings,
   launchedFromSave: launchedFromSave)
  view.applyCameraSettings(to: scene)
  view.renderer.projectionConfiguration.fieldOfViewDegrees = view.settings.fieldOfViewDegrees
  view.updateOverlayViews()
  return view
 }

 override init(frame frameRect: NSRect) {
  fatalError("Use MetalView.make(frame:) to build a configured MetalView")
 }

 private init(
  configuredFrame frameRect: NSRect,
  scene: GameScene,
  inputController: GameInputController,
  device: MTLDevice,
  renderer: Renderer,
  debugHUDView: DebugHUDView,
  minimapView: MinimapView,
  crosshairView: CrosshairView,
  helpOverlayView: HelpOverlayView,
  debugControlPanelView: DebugControlPanelView,
  statusBannerView: StatusBannerView,
  hotbarView: HotbarView,
  settings: SettingsStore,
  launchedFromSave: Bool
 ) {
  self.scene = scene
  self.inputController = inputController
  self.device = device
  self.renderer = renderer
  self.debugHUDView = debugHUDView
  self.minimapView = minimapView
  self.crosshairView = crosshairView
  self.helpOverlayView = helpOverlayView
  self.debugControlPanelView = debugControlPanelView
  self.statusBannerView = statusBannerView
  self.hotbarView = hotbarView
  self.settings = settings
  self.renderScale = CGFloat(settings.renderScale)
  self.launchedFromSave = launchedFromSave

  super.init(frame: frameRect)

  wantsLayer = true
  configureMetalLayer()
  configureOverlayViews()
  configureDebugControlCallbacks()
  updateOverlayViews()

  let gameLoop = GameLoop { [weak self] dt in
   self?.advanceFrame(dt: dt)
  }
  self.gameLoop = gameLoop
 }

 required init?(coder: NSCoder) {
  fatalError("init(coder:) has not been implemented")
 }

 override func makeBackingLayer() -> CALayer {
  CAMetalLayer()
 }

 override var acceptsFirstResponder: Bool {
  true
 }

 override var frame: NSRect {
  didSet {
   updateDrawableSize()
  }
 }

 override func viewDidMoveToWindow() {
  super.viewDidMoveToWindow()
  updateDrawableSize()
  registerWindowObserversIfNeeded()
  updateWindowTitle()

  if window != nil {
   gameLoop?.start()
   updateInteractiveState()
   soundEngine.setEnabled(settings.soundEnabled)
   soundEngine.setMasterVolume(settings.masterVolume)
   soundEngine.start()
   if !hasShownWelcomeHint {
    hasShownWelcomeHint = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
     guard let self else { return }
     self.showStatusBanner(
      self.launchedFromSave
       ? "Loaded saved world — seed \(self.currentWorldSeed)"
       : "Generated new world — seed \(self.currentWorldSeed)",
      duration: 2.4)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
     self?.showStatusBanner(
      "WASD move · Shift sprint · F fly · 1–8 blocks · ⌘? controls",
      duration: 3.6)
    }
   }
  }
 }

 override func viewWillMove(toWindow newWindow: NSWindow?) {
  if observedWindow !== newWindow {
   unregisterWindowObservers()
  }
  if newWindow == nil {
   gameLoop?.stop()
   setMouseCapture(enabled: false)
  }

  super.viewWillMove(toWindow: newWindow)
 }

 func handleEvent(_ event: NSEvent) {
  inputController.handle(event, gameplayInputEnabled: !isDebugPanelModeEnabled)
 }

 override func scrollWheel(with event: NSEvent) {
  // The AppDelegate event monitor doesn't watch scroll events, so the normal responder
  // chain delivers them here. Route them to the input controller like every other event.
  inputController.handle(event, gameplayInputEnabled: !isDebugPanelModeEnabled)
 }

 private func configureMetalLayer() {
  metalLayer.device = device
  metalLayer.pixelFormat = .bgra8Unorm
  metalLayer.framebufferOnly = true
  updateDrawableSize()
 }

 private func configureOverlayViews() {
  addSubview(debugHUDView)
  addSubview(minimapView)
  addSubview(crosshairView)
  addSubview(helpOverlayView)
  addSubview(debugControlPanelView)
  addSubview(statusBannerView)
  addSubview(hotbarView)

  NSLayoutConstraint.activate([
   // The hotbar sits along the bottom center; the compact HUD stacks just above it.
   hotbarView.centerXAnchor.constraint(equalTo: centerXAnchor),
   hotbarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

   debugHUDView.centerXAnchor.constraint(equalTo: centerXAnchor),
   debugHUDView.bottomAnchor.constraint(equalTo: hotbarView.topAnchor, constant: -10),

   minimapView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
   minimapView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
   minimapView.widthAnchor.constraint(equalToConstant: 160),
   minimapView.heightAnchor.constraint(equalToConstant: 160),

   crosshairView.centerXAnchor.constraint(equalTo: centerXAnchor),
   crosshairView.centerYAnchor.constraint(equalTo: centerYAnchor),
   crosshairView.widthAnchor.constraint(equalToConstant: 24),
   crosshairView.heightAnchor.constraint(equalToConstant: 24),

   helpOverlayView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
   helpOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

   debugControlPanelView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
   debugControlPanelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

   statusBannerView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
   statusBannerView.centerXAnchor.constraint(equalTo: centerXAnchor),
  ])
 }

 private func configureDebugControlCallbacks() {
  debugControlPanelView.onMaterialModeChanged = { [weak self] mode in
   self?.setMaterialDebugMode(mode)
  }
  debugControlPanelView.onLODOverlayModeChanged = { [weak self] mode in
   self?.renderer.debugSettings.lodTintOverlayMode = mode
   self?.showStatusBanner("LOD tint: \(mode.displayName)")
   self?.updateOverlayViews()
  }
  debugControlPanelView.onBlockMaterialChanged = { [weak self] material in
   self?.scene.selectedPlacementMaterial = material
   self?.showStatusBanner("Placed block: \(material.displayName)")
   self?.updateOverlayViews()
  }
  debugControlPanelView.onFrustumChanged = { [weak self] value in
   self?.renderer.debugSettings.frustumCullingEnabled = value
   self?.showStatusBanner(value ? "Frustum culling on" : "Frustum culling off")
  }
  debugControlPanelView.onOcclusionChanged = { [weak self] value in
   self?.renderer.debugSettings.occlusionCullingEnabled = value
   self?.showStatusBanner(value ? "Occlusion culling on" : "Occlusion culling off")
  }
  debugControlPanelView.onLODChanged = { [weak self] value in
   self?.renderer.debugSettings.lodEnabled = value
   self?.showStatusBanner(value ? "LOD meshing on" : "LOD meshing off")
   self?.updateOverlayViews()
  }
  debugControlPanelView.onHUDChanged = { [weak self] value in
   self?.setHUDVisibility(value)
  }
  debugControlPanelView.onMinimapChanged = { [weak self] value in
   self?.setMinimapVisibility(value)
  }
  debugControlPanelView.onCrosshairChanged = { [weak self] value in
   self?.isCrosshairVisible = value
   self?.showStatusBanner(value ? "Crosshair shown" : "Crosshair hidden")
   self?.updateOverlayViews()
  }

  debugControlPanelView.onLookSensitivityChanged = { [weak self] value in
   self?.setLookSensitivity(value)
  }
  debugControlPanelView.onFieldOfViewChanged = { [weak self] value in
   self?.setFieldOfView(value)
  }
 }

 private func updateDrawableSize() {
  let drawableSize = Self.makeDrawableSize(
   for: frame,
   backingScaleFactor: window?.backingScaleFactor,
   renderScale: renderScale)
  metalLayer.drawableSize = drawableSize
  renderer.resize(drawableSize: drawableSize)
 }

 private func advanceFrame(dt: Float) {
  autoreleasepool {
   if inputController.consumePanelToggle() {
    toggleDebugPanelMode()
   }
   if inputController.consumeFlyToggle() {
    scene.player.toggleFlying()
    showStatusBanner(scene.player.isFlying ? "Fly mode on" : "Fly mode off")
   }
   if inputController.consumeEscape() {
    if isDebugPanelModeEnabled {
     toggleDebugPanelMode()  // Close the inspector
    } else if isMouseCaptured {
     setMouseCapture(enabled: false)
     isHelpVisible = true  // Re-show the Controls overlay
    } else {
     setMouseCapture(enabled: true)
    }
   }

   if inputController.consumeMaterialDebugToggle() {
    cycleMaterialDebugMode()
   }
   if inputController.consumeHUDToggle() {
    toggleHUDVisibility()
   }
   if let material = inputController.consumeBlockMaterialSelection() {
    scene.selectedPlacementMaterial = material
    showStatusBanner("Placed block: \(material.displayName)")
    updateOverlayViews()
   }
   let materialCycle = inputController.consumeMaterialCycle()
   if materialCycle != 0 {
    cyclePlacementMaterial(by: materialCycle)
   }

   if !isDebugPanelModeEnabled {
    let lookDelta = inputController.consumeLookDelta()
    let editActions = inputController.consumeEditActions()
    let world = scene.world
    let revisionBeforeUpdate = world.meshRevision
    scene.update(
     dt: dt, input: inputController.currentInput, lookDelta: lookDelta,
     editActions: editActions)
    // A revision bump means an edit really landed (placements that would
    // intersect the player are rejected and stay silent).
    if world.meshRevision != revisionBeforeUpdate {
     if editActions.contains(.remove) {
      soundEngine.playBlockRemoved()
     } else if editActions.contains(.place) {
      soundEngine.playBlockPlaced()
     }
    }
    updateLocomotionAudio(dt: dt)
   }

   do {
    try renderer.render(
     into: metalLayer,
     world: scene.world,
     camera: scene.camera,
     selectedHit: scene.currentTarget,
     editFeedback: scene.currentEditFeedback)
    updateOverlayViews(frameTimeSeconds: dt)
   } catch {
    presentRuntimeErrorOnce(error)
   }
  }
 }

 private func updateOverlayViews(frameTimeSeconds: Float = 0) {
  // The overlays are driven from a single snapshot so the HUD, minimap, and inspector all
  // describe the same frame of world/render state.
  let snapshot = DebugHUDSnapshot(
   scene: scene,
   renderer: renderer,
   frameTimeSeconds: frameTimeSeconds)

  helpOverlayView.isHidden = !isHelpVisible
  debugHUDView.isHidden = !isHUDVisible
  minimapView.isHidden = !isMinimapVisible
  crosshairView.isHidden = !isCrosshairVisible
  hotbarView.isHidden = !isHUDVisible

  helpOverlayView.update(mouseCaptured: isMouseCaptured)
  debugHUDView.update(snapshot: snapshot)
  minimapView.update(snapshot: MinimapSnapshot(scene: scene))
  crosshairView.update(
   hasTarget: scene.currentTarget != nil, editFeedback: scene.currentEditFeedback)
  hotbarView.update(selected: scene.selectedPlacementMaterial)
  debugControlPanelView.update(
   materialMode: renderer.debugSettings.materialMode,
   lodTintOverlayMode: renderer.debugSettings.lodTintOverlayMode,
   blockMaterial: scene.selectedPlacementMaterial,
   lookSensitivity: scene.player.cameraConfiguration.lookSensitivity,
   fieldOfViewDegrees: renderer.projectionConfiguration.fieldOfViewDegrees,
   frustumEnabled: renderer.debugSettings.frustumCullingEnabled,
   occlusionEnabled: renderer.debugSettings.occlusionCullingEnabled,
   lodEnabled: renderer.debugSettings.lodEnabled,
   hudVisible: isHUDVisible,
   minimapVisible: isMinimapVisible,
   crosshairVisible: isCrosshairVisible,
   snapshot: snapshot)
 }

 func toggleHelpOverlay() {
  isHelpVisible.toggle()
  showStatusBanner(isHelpVisible ? "Controls overlay shown" : "Controls overlay hidden")
  updateOverlayViews()
 }

 func toggleDebugInspector() {
  toggleDebugPanelMode()
 }

 func toggleHUDVisibility() {
  setHUDVisibility(!isHUDVisible)
 }

 func toggleMinimapVisibility() {
  setMinimapVisibility(!isMinimapVisible)
 }

 func toggleCrosshairVisibility() {
  isCrosshairVisible.toggle()
  showStatusBanner(isCrosshairVisible ? "Crosshair shown" : "Crosshair hidden")
  updateOverlayViews()
 }

 func cycleMaterialDebugMode() {
  setMaterialDebugMode(renderer.materialDebugMode.next())
 }

 private func updateLocomotionAudio(dt: Float) {
  let player = scene.player
  let grounded = player.isGrounded
  let velocity = player.velocity
  let horizontalSpeed = (velocity.x * velocity.x + velocity.z * velocity.z).squareRoot()

  if grounded && !wasGroundedLastFrame && previousVerticalVelocity < -6 {
   // Just touched down after a real fall.
   soundEngine.playLanding()
   footstepDistanceAccumulator = 0
  } else if grounded && !player.isFlying && horizontalSpeed > 0.5 {
   // One footstep every ~2.2 world units walked; sprinting speeds the cadence
   // naturally because the accumulator fills faster.
   footstepDistanceAccumulator += horizontalSpeed * dt
   if footstepDistanceAccumulator >= 2.2 {
    footstepDistanceAccumulator -= 2.2
    soundEngine.playFootstep()
   }
  } else {
   footstepDistanceAccumulator = 0
  }

  wasGroundedLastFrame = grounded
  previousVerticalVelocity = velocity.y
 }

 /// Moves the hotbar selection by `steps` (wrapping), for scroll-wheel cycling.
 private func cyclePlacementMaterial(by steps: Int) {
  let all = BlockMaterialType.allCases
  guard let current = all.firstIndex(of: scene.selectedPlacementMaterial) else { return }
  let count = all.count
  let next = ((current + steps) % count + count) % count
  let material = all[next]
  scene.selectedPlacementMaterial = material
  showStatusBanner("Placed block: \(material.displayName)")
  updateOverlayViews()
 }

 private var overlayViews: [NSView] {
  [
   debugHUDView,
   minimapView,
   crosshairView,
   helpOverlayView,
   debugControlPanelView,
   statusBannerView,
   hotbarView,
  ]
 }

 private func toggleDebugPanelMode() {
  isDebugPanelModeEnabled.toggle()
  inputController.cancelGameplayInput()
  debugControlPanelView.isHidden = !isDebugPanelModeEnabled
  updateInteractiveState()
  showStatusBanner(
   isDebugPanelModeEnabled ? "Debug inspector opened" : "Debug inspector closed")
 }

 private func setHUDVisibility(_ value: Bool) {
  isHUDVisible = value
  showStatusBanner(value ? "Compact HUD shown" : "Compact HUD hidden")
  updateOverlayViews()
 }

 private func setMinimapVisibility(_ value: Bool) {
  isMinimapVisible = value
  showStatusBanner(value ? "Minimap shown" : "Minimap hidden")
  updateOverlayViews()
 }

 private func setMaterialDebugMode(_ mode: MaterialDebugMode) {
  renderer.materialDebugMode = mode
  showStatusBanner("Material view: \(mode.displayName)")
  updateOverlayViews()
 }

 private func registerWindowObserversIfNeeded() {
  guard let window, observedWindow !== window else {
   return
  }

  unregisterWindowObservers()
  observedWindow = window
  NotificationCenter.default.addObserver(
   self,
   selector: #selector(windowKeyStateChanged(_:)),
   name: NSWindow.didBecomeKeyNotification,
   object: window)
  NotificationCenter.default.addObserver(
   self,
   selector: #selector(windowKeyStateChanged(_:)),
   name: NSWindow.didResignKeyNotification,
   object: window)
 }

 private func unregisterWindowObservers() {
  guard let observedWindow else {
   return
  }

  NotificationCenter.default.removeObserver(
   self,
   name: NSWindow.didBecomeKeyNotification,
   object: observedWindow)
  NotificationCenter.default.removeObserver(
   self,
   name: NSWindow.didResignKeyNotification,
   object: observedWindow)
  self.observedWindow = nil
 }

 @objc private func windowKeyStateChanged(_ notification: Notification) {
  if window?.isKeyWindow != true {
   // The window lost key focus (cmd-tab, click-away). A movement key held at that moment
   // never gets its key-up event, so without this the player keeps walking while we're
   // backgrounded. Clear held gameplay input before updating cursor capture.
   inputController.cancelGameplayInput()
  }
  updateInteractiveState()
 }

 private func updateInteractiveState() {
  // Cursor capture should follow actual playability, not just "the view exists". Releasing
  // on resign-key keeps the desktop usable when the user alt-tabs away, and recapturing on
  // become-key restores the immersive mouse-look flow when they come back.
  let shouldCaptureMouse =
   window?.isKeyWindow == true
   && !isDebugPanelModeEnabled
   && !hasPresentedRuntimeError
  setMouseCapture(enabled: shouldCaptureMouse)
 }

 private func setMouseCapture(enabled: Bool) {
  guard enabled != isMouseCaptured else {
   return
  }

  if enabled {
   NSCursor.hide()
   CGAssociateMouseAndMouseCursorPosition(0)
   isMouseCaptured = true
  } else {
   CGAssociateMouseAndMouseCursorPosition(1)
   NSCursor.unhide()
   isMouseCaptured = false
  }
 }

 private func presentRuntimeErrorOnce(_ error: Error) {
  guard !hasPresentedRuntimeError else {
   return
  }

  hasPresentedRuntimeError = true
  gameLoop?.stop()
  updateInteractiveState()
  NSApp.presentError(error)
 }

 private func showStatusBanner(_ message: String) {
  statusBannerView.show(message: message)
 }

 private func showStatusBanner(_ message: String, duration: TimeInterval) {
  statusBannerView.show(message: message, duration: duration)
 }

 // MARK: - World persistence

 static let worldSaveURL: URL = {
  let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
   // Historical folder name from before the engine/demo split (the app
   // target used to be called `VoxelGame`). Kept verbatim so previously
   // saved worlds keep loading.
   .appendingPathComponent("VoxelGame", isDirectory: true)
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir.appendingPathComponent("world.vxsave")
 }()

 /// The seed that originally generated the current world (0 for `.empty` worlds,
 /// which the app never creates through its own flows).
 private var currentWorldSeed: UInt64 {
  if case .terrain(let config) = scene.world.generation { return config.seed }
  return 0
 }

 /// Rebuilds a scene from a decoded save. Returns nil when the save's dimensions
 /// don't match the app's world size or the grid data is invalid.
 private static func sceneFromSaveState(_ state: WorldSaveState) -> GameScene? {
  guard state.gridSize == 256, state.chunkSize == 16,
   let world = VoxelWorld.restored(
    gridSize: state.gridSize, chunkSize: state.chunkSize,
    seed: state.seed, words: state.solidWords, materials: state.materials)
  else { return nil }
  let player = PlayerController(
   position: state.playerPosition,
   cameraYaw: state.cameraYaw,
   cameraPitch: state.cameraPitch,
   isFlying: state.isFlying)
  let scene = GameScene(world: world, player: player)
  scene.selectedPlacementMaterial = state.selectedMaterial
  return scene
 }

 /// Every world swap builds a fresh player, so reapply the persisted camera feel
 /// instead of falling back to compile-time defaults until the next relaunch.
 private func applyCameraSettings(to scene: GameScene) {
  scene.player.cameraConfiguration.lookSensitivity = settings.lookSensitivity
  scene.player.cameraConfiguration.invertLookY = settings.invertLookY
 }

 /// Every world change (new/load/reset) funnels through here so the renderer,
 /// input state, window title, and overlays stay consistent.
 private func adoptScene(_ newScene: GameScene, banner: String) {
  applyCameraSettings(to: newScene)
  scene = newScene
  renderer.resetWorldSynchronization(with: newScene.world)
  inputController.cancelGameplayInput()
  updateWindowTitle()
  showStatusBanner(banner)
  updateOverlayViews()
 }

 func updateWindowTitle() {
  window?.title = "VoxelDemo — Seed \(currentWorldSeed)"
 }

 private func currentSaveState() -> WorldSaveState {
  let snapshot = scene.world.makeSaveSnapshot()
  return WorldSaveState(
   gridSize: scene.world.gridSize,
   chunkSize: scene.world.chunkSize,
   seed: currentWorldSeed,
   playerPosition: scene.player.position,
   cameraYaw: scene.player.cameraYaw,
   cameraPitch: scene.player.cameraPitch,
   isFlying: scene.player.isFlying,
   selectedMaterial: scene.selectedPlacementMaterial,
   solidWords: snapshot.words,
   materials: snapshot.materials)
 }

 func saveWorldToDisk() {
  let data = WorldSaveCodec.encode(currentSaveState())
  do {
   try data.write(to: Self.worldSaveURL, options: .atomic)
   showStatusBanner("World saved — seed \(currentWorldSeed)")
  } catch {
   showStatusBanner("Could not save world")
  }
 }

 func saveWorldAs() {
  setMouseCapture(enabled: false)
  let panel = NSSavePanel()
  panel.nameFieldStringValue = "world.vxsave"
  panel.directoryURL = Self.worldSaveURL.deletingLastPathComponent()
  if let type = UTType(filenameExtension: "vxsave") {
   panel.allowedContentTypes = [type]
  }
  guard panel.runModal() == .OK, let url = panel.url else { return }
  do {
   try WorldSaveCodec.encode(currentSaveState()).write(to: url, options: .atomic)
   RecentWorldsStore().note(url.path)
   showStatusBanner("\(url.lastPathComponent) saved — seed \(currentWorldSeed)")
  } catch {
   showStatusBanner("Could not save world")
  }
 }

 /// Loads a world file and swaps it in. Returns false when the file is missing,
 /// corrupt, or was saved with different world dimensions.
 func loadWorld(from url: URL) -> Bool {
  guard let data = try? Data(contentsOf: url),
   let state = WorldSaveCodec.decode(data),
   let restoredScene = Self.sceneFromSaveState(state)
  else { return false }
  adoptScene(restoredScene, banner: "Loaded world — seed \(state.seed)")
  return true
 }

 func revertToSaved() {
  if !loadWorld(from: Self.worldSaveURL) {
   showStatusBanner("No saved world yet")
  }
 }

 func openWorld() {
  setMouseCapture(enabled: false)
  let panel = NSOpenPanel()
  panel.allowsMultipleSelection = false
  panel.directoryURL = Self.worldSaveURL.deletingLastPathComponent()
  if let type = UTType(filenameExtension: "vxsave") {
   panel.allowedContentTypes = [type]
  }
  guard panel.runModal() == .OK, let url = panel.url else { return }
  if !loadWorld(from: url) {
   showStatusBanner("Could not open that world file")
  } else {
   RecentWorldsStore().note(url.path)
  }
 }

 func newWorld(seed: UInt64) {
  adoptScene(
   GameScene(
    gridSize: 256,
    worldGeneration: .terrain(VoxelWorldConfiguration(seed: seed))),
   banner: "New world — seed \(seed)")
 }

 func newRandomWorld() {
  newWorld(seed: UInt64.random(in: .min ... .max))
 }

 func promptForSeedAndCreateWorld() {
  setMouseCapture(enabled: false)
  let alert = NSAlert()
  alert.messageText = "New World from Seed"
  alert.informativeText =
   "Type a number to use it directly, or any text to derive a seed from it."
  alert.addButton(withTitle: "Create")
  alert.addButton(withTitle: "Cancel")
  let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
  alert.accessoryView = field
  alert.window.initialFirstResponder = field
  guard alert.runModal() == .alertFirstButtonReturn,
   let seed = WorldSeedParser.seed(from: field.stringValue)
  else { return }
  newWorld(seed: seed)
 }

 func resetWorld() {
  setMouseCapture(enabled: false)
  let seed = currentWorldSeed
  let alert = NSAlert()
  alert.messageText = "Reset the world?"
  alert.informativeText =
   "Terrain edits in this world will be discarded and the terrain regenerates from seed \(seed)."
  alert.addButton(withTitle: "Reset")
  alert.addButton(withTitle: "Cancel")
  guard alert.runModal() == .alertFirstButtonReturn else { return }
  try? FileManager.default.removeItem(at: Self.worldSaveURL)
  adoptScene(
   GameScene(
    gridSize: 256,
    worldGeneration: .terrain(VoxelWorldConfiguration(seed: seed))),
   banner: "World reset — seed \(seed)")
 }

 func toggleFlyModeFromMenu() {
  scene.player.toggleFlying()
  showStatusBanner(scene.player.isFlying ? "Fly mode on" : "Fly mode off")
 }

 // MARK: - Menu state + sharing

 var isPlayerFlying: Bool { scene.player.isFlying }

 var isSoundEnabled: Bool { soundEngine.isEnabled }

 func setLookSensitivity(_ value: Float) {
  settings.lookSensitivity = value
  scene.player.cameraConfiguration.lookSensitivity = settings.lookSensitivity
  updateOverlayViews()
 }

 func setFieldOfView(_ value: Float) {
  settings.fieldOfViewDegrees = value
  renderer.projectionConfiguration.fieldOfViewDegrees = settings.fieldOfViewDegrees
  updateOverlayViews()
 }

 func setInvertLookY(_ value: Bool) {
  settings.invertLookY = value
  scene.player.cameraConfiguration.invertLookY = settings.invertLookY
 }

 func setRenderScale(_ scale: CGFloat) {
  let clampedScale = min(max(scale, 0.5), 2.0)
  guard abs(clampedScale - renderScale) > 0.0001 else { return }
  renderScale = clampedScale
  settings.renderScale = Float(clampedScale)
  updateDrawableSize()
  showStatusBanner("Render resolution \(Int(clampedScale * 100))%")
 }

 func setSoundEnabled(_ value: Bool) {
  settings.soundEnabled = value
  soundEngine.setEnabled(settings.soundEnabled)
 }

 func setMasterVolume(_ value: Float) {
  settings.masterVolume = value
  soundEngine.setMasterVolume(settings.masterVolume)
 }

 func toggleSoundEffects() {
  let enabled = !soundEngine.isEnabled
  setSoundEnabled(enabled)
  showStatusBanner(enabled ? "Sound effects on" : "Sound effects off")
 }

 func copyWorldSeed() {
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.setString("\(currentWorldSeed)", forType: .string)
  showStatusBanner("Seed \(currentWorldSeed) copied — paste it into New World from Seed")
 }

 /// Opens a world picked from the File ▸ Open Recent menu; prunes entries whose
 /// files no longer exist or fail to decode.
 func openRecentWorld(atPath path: String) {
  if loadWorld(from: URL(fileURLWithPath: path)) {
   RecentWorldsStore().note(path)
  } else {
   RecentWorldsStore().remove(path)
   showStatusBanner("Could not open that world file")
  }
 }

 func clearRecentWorlds() {
  RecentWorldsStore().clear()
 }

 var currentRenderScale: CGFloat { renderScale }

 /// Rendering below native resolution is the fastest GPU lever in the demo, and the
 /// CAMetalLayer scales the smaller drawable back up to the window for free.
 nonisolated static func makeDrawableSize(
  for frame: NSRect,
  backingScaleFactor: CGFloat?,
  renderScale: CGFloat
 ) -> CGSize {
  let scale = backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
  return CGSize(
   width: max(1, floor(frame.width * scale * renderScale)),
   height: max(1, floor(frame.height * scale * renderScale)))
 }
}

enum MetalViewError: LocalizedError, Equatable {
 case metalUnavailable

 var errorDescription: String? {
  switch self {
  case .metalUnavailable:
   return "Metal is not supported on this device."
  }
 }
}
