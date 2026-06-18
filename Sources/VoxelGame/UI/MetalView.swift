import Cocoa
import CoreGraphics
import Metal
import QuartzCore
import VoxelGameKit

@MainActor
final class MetalView: NSView {
    private let scene: GameScene
    private let inputController: GameInputController
    private let device: MTLDevice
    private let renderer: Renderer
    private let debugHUDView: DebugHUDView
    private let minimapView: MinimapView
    private let crosshairView: CrosshairView
    private let debugControlPanelView: DebugControlPanelView
    private let statusBannerView: StatusBannerView

    private var gameLoop: GameLoop?
    private var hasPresentedRuntimeError = false
    private var isDebugPanelModeEnabled = false
    private var isHUDVisible = true
    private var isMinimapVisible = true
    private var isCrosshairVisible = true
    private var isMouseCaptured = false
    private var hasShownWelcomeHint = false

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

        let scene = GameScene(gridSize: 256)
        let inputController = GameInputController()
        let drawableSize = makeDrawableSize(for: frame, backingScaleFactor: nil)
        let renderer = try Renderer(device: device, world: scene.world, drawableSize: drawableSize)
        let debugHUDView = DebugHUDView(frame: .zero)
        let minimapView = MinimapView(frame: .zero)
        let crosshairView = CrosshairView(frame: .zero)
        let debugControlPanelView = DebugControlPanelView(frame: .zero)
        let statusBannerView = StatusBannerView(frame: .zero)

        return MetalView(
            configuredFrame: frame,
            scene: scene,
            inputController: inputController,
            device: device,
            renderer: renderer,
            debugHUDView: debugHUDView,
            minimapView: minimapView,
            crosshairView: crosshairView,
            debugControlPanelView: debugControlPanelView,
            statusBannerView: statusBannerView)
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
        debugControlPanelView: DebugControlPanelView,
        statusBannerView: StatusBannerView
    ) {
        self.scene = scene
        self.inputController = inputController
        self.device = device
        self.renderer = renderer
        self.debugHUDView = debugHUDView
        self.minimapView = minimapView
        self.crosshairView = crosshairView
        self.debugControlPanelView = debugControlPanelView
        self.statusBannerView = statusBannerView

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
        gameLoop.start()
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
        if window != nil && !isDebugPanelModeEnabled && !hasPresentedRuntimeError {
            setMouseCapture(enabled: true)
            if !hasShownWelcomeHint {
                hasShownWelcomeHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.showStatusBanner(
                        "Tab debug inspector  ·  1–5 switch block  ·  F1 toggle HUD", duration: 2.8)
                }
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            gameLoop?.stop()
            setMouseCapture(enabled: false)
        }

        super.viewWillMove(toWindow: newWindow)
    }

    func handleEvent(_ event: NSEvent) {
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
        addSubview(debugControlPanelView)
        addSubview(statusBannerView)

        NSLayoutConstraint.activate([
            debugHUDView.centerXAnchor.constraint(equalTo: centerXAnchor),
            debugHUDView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            minimapView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            minimapView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            minimapView.widthAnchor.constraint(equalToConstant: 160),
            minimapView.heightAnchor.constraint(equalToConstant: 160),

            crosshairView.centerXAnchor.constraint(equalTo: centerXAnchor),
            crosshairView.centerYAnchor.constraint(equalTo: centerYAnchor),
            crosshairView.widthAnchor.constraint(equalToConstant: 24),
            crosshairView.heightAnchor.constraint(equalToConstant: 24),

            debugControlPanelView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            debugControlPanelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            statusBannerView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            statusBannerView.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func configureDebugControlCallbacks() {
        debugControlPanelView.onMaterialModeChanged = { [weak self] mode in
            self?.renderer.debugSettings.materialMode = mode
            self?.showStatusBanner("Material view: \(mode.displayName)")
            self?.updateOverlayViews()
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
            self?.isHUDVisible = value
            self?.showStatusBanner(value ? "Compact HUD shown" : "Compact HUD hidden")
            self?.updateOverlayViews()
        }
        debugControlPanelView.onMinimapChanged = { [weak self] value in
            self?.isMinimapVisible = value
            self?.showStatusBanner(value ? "Minimap shown" : "Minimap hidden")
            self?.updateOverlayViews()
        }
        debugControlPanelView.onCrosshairChanged = { [weak self] value in
            self?.isCrosshairVisible = value
            self?.showStatusBanner(value ? "Crosshair shown" : "Crosshair hidden")
            self?.updateOverlayViews()
        }
    }

    private func updateDrawableSize() {
        let drawableSize = Self.makeDrawableSize(
            for: frame,
            backingScaleFactor: window?.backingScaleFactor)
        metalLayer.drawableSize = drawableSize
        renderer.resize(drawableSize: drawableSize)
    }

    private func advanceFrame(dt: Float) {
        autoreleasepool {
            if inputController.consumePanelToggle() {
                toggleDebugPanelMode()
            }

            if inputController.consumeMaterialDebugToggle() {
                renderer.materialDebugMode = renderer.materialDebugMode.next()
                showStatusBanner("Material view: \(renderer.materialDebugMode.displayName)")
            }
            if inputController.consumeHUDToggle() {
                isHUDVisible.toggle()
                showStatusBanner(isHUDVisible ? "Compact HUD shown" : "Compact HUD hidden")
            }
            if let material = inputController.consumeBlockMaterialSelection() {
                scene.selectedPlacementMaterial = material
                showStatusBanner("Placed block: \(material.displayName)")
                updateOverlayViews()
            }

            if !isDebugPanelModeEnabled {
                let lookDelta = inputController.consumeLookDelta()
                let editActions = inputController.consumeEditActions()
                scene.update(
                    dt: dt, input: inputController.currentInput, lookDelta: lookDelta,
                    editActions: editActions)
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
        let snapshot = DebugHUDSnapshot(
            scene: scene,
            renderer: renderer,
            frameTimeSeconds: frameTimeSeconds)

        debugHUDView.isHidden = !isHUDVisible
        minimapView.isHidden = !isMinimapVisible
        crosshairView.isHidden = !isCrosshairVisible

        debugHUDView.update(snapshot: snapshot)
        minimapView.update(snapshot: MinimapSnapshot(scene: scene))
        crosshairView.update(
            hasTarget: scene.currentTarget != nil, editFeedback: scene.currentEditFeedback)
        debugControlPanelView.update(
            materialMode: renderer.debugSettings.materialMode,
            lodTintOverlayMode: renderer.debugSettings.lodTintOverlayMode,
            blockMaterial: scene.selectedPlacementMaterial,
            frustumEnabled: renderer.debugSettings.frustumCullingEnabled,
            occlusionEnabled: renderer.debugSettings.occlusionCullingEnabled,
            lodEnabled: renderer.debugSettings.lodEnabled,
            hudVisible: isHUDVisible,
            minimapVisible: isMinimapVisible,
            crosshairVisible: isCrosshairVisible,
            snapshot: snapshot)
    }

    private func toggleDebugPanelMode() {
        isDebugPanelModeEnabled.toggle()
        inputController.cancelGameplayInput()
        debugControlPanelView.isHidden = !isDebugPanelModeEnabled
        setMouseCapture(enabled: !isDebugPanelModeEnabled)
        showStatusBanner(
            isDebugPanelModeEnabled ? "Debug inspector opened" : "Debug inspector closed")
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
        setMouseCapture(enabled: false)
        NSApp.presentError(error)
    }

    private func showStatusBanner(_ message: String) {
        statusBannerView.show(message: message)
    }

    private func showStatusBanner(_ message: String, duration: TimeInterval) {
        statusBannerView.show(message: message, duration: duration)
    }

    private static func makeDrawableSize(for frame: NSRect, backingScaleFactor: CGFloat?) -> CGSize
    {
        let scale = backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return CGSize(width: frame.width * scale, height: frame.height * scale)
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
