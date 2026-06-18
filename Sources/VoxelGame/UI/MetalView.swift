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

    private var gameLoop: GameLoop?
    private var hasPresentedRuntimeError = false
    private var isDebugPanelModeEnabled = false
    private var isHUDVisible = true
    private var isMinimapVisible = true
    private var isCrosshairVisible = true

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

        return MetalView(
            configuredFrame: frame,
            scene: scene,
            inputController: inputController,
            device: device,
            renderer: renderer,
            debugHUDView: debugHUDView,
            minimapView: minimapView,
            crosshairView: crosshairView,
            debugControlPanelView: debugControlPanelView)
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
        debugControlPanelView: DebugControlPanelView
    ) {
        self.scene = scene
        self.inputController = inputController
        self.device = device
        self.renderer = renderer
        self.debugHUDView = debugHUDView
        self.minimapView = minimapView
        self.crosshairView = crosshairView
        self.debugControlPanelView = debugControlPanelView

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

        NSLayoutConstraint.activate([
            debugHUDView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            debugHUDView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            minimapView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            minimapView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            minimapView.widthAnchor.constraint(equalToConstant: 180),
            minimapView.heightAnchor.constraint(equalToConstant: 180),

            crosshairView.centerXAnchor.constraint(equalTo: centerXAnchor),
            crosshairView.centerYAnchor.constraint(equalTo: centerYAnchor),
            crosshairView.widthAnchor.constraint(equalToConstant: 24),
            crosshairView.heightAnchor.constraint(equalToConstant: 24),

            debugControlPanelView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            debugControlPanelView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    private func configureDebugControlCallbacks() {
        debugControlPanelView.onMaterialModeChanged = { [weak self] mode in
            self?.renderer.debugSettings.materialMode = mode
            self?.updateOverlayViews()
        }
        debugControlPanelView.onLODOverlayModeChanged = { [weak self] mode in
            self?.renderer.debugSettings.lodTintOverlayMode = mode
            self?.updateOverlayViews()
        }
        debugControlPanelView.onBlockMaterialChanged = { [weak self] material in
            self?.scene.selectedPlacementMaterial = material
            self?.updateOverlayViews()
        }
        debugControlPanelView.onFrustumChanged = { [weak self] value in
            self?.renderer.debugSettings.frustumCullingEnabled = value
        }
        debugControlPanelView.onOcclusionChanged = { [weak self] value in
            self?.renderer.debugSettings.occlusionCullingEnabled = value
        }
        debugControlPanelView.onLODChanged = { [weak self] value in
            self?.renderer.debugSettings.lodEnabled = value
            self?.updateOverlayViews()
        }
        debugControlPanelView.onHUDChanged = { [weak self] value in
            self?.isHUDVisible = value
            self?.debugHUDView.isHidden = !value
        }
        debugControlPanelView.onMinimapChanged = { [weak self] value in
            self?.isMinimapVisible = value
            self?.minimapView.isHidden = !value
        }
        debugControlPanelView.onCrosshairChanged = { [weak self] value in
            self?.isCrosshairVisible = value
            self?.crosshairView.isHidden = !value
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

            guard !isDebugPanelModeEnabled else {
                updateOverlayViews(frameTimeSeconds: dt)
                return
            }

            if inputController.consumeMaterialDebugToggle() {
                renderer.materialDebugMode = renderer.materialDebugMode.next()
            }
            if inputController.consumeHUDToggle() {
                isHUDVisible.toggle()
                debugHUDView.isHidden = !isHUDVisible
            }
            if let material = inputController.consumeBlockMaterialSelection() {
                scene.selectedPlacementMaterial = material
                updateOverlayViews()
            }

            let lookDelta = inputController.consumeLookDelta()
            let editActions = inputController.consumeEditActions()
            scene.update(
                dt: dt, input: inputController.currentInput, lookDelta: lookDelta,
                editActions: editActions)

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
        debugHUDView.isHidden = !isHUDVisible
        minimapView.isHidden = !isMinimapVisible
        crosshairView.isHidden = !isCrosshairVisible

        debugHUDView.update(
            snapshot: DebugHUDSnapshot(
                scene: scene,
                renderer: renderer,
                frameTimeSeconds: frameTimeSeconds))
        minimapView.update(snapshot: MinimapSnapshot(scene: scene))
        crosshairView.update(hasTarget: scene.currentTarget != nil)
        debugControlPanelView.update(
            materialMode: renderer.debugSettings.materialMode,
            lodTintOverlayMode: renderer.debugSettings.lodTintOverlayMode,
            blockMaterial: scene.selectedPlacementMaterial,
            frustumEnabled: renderer.debugSettings.frustumCullingEnabled,
            occlusionEnabled: renderer.debugSettings.occlusionCullingEnabled,
            lodEnabled: renderer.debugSettings.lodEnabled,
            hudVisible: isHUDVisible,
            minimapVisible: isMinimapVisible,
            crosshairVisible: isCrosshairVisible)
    }

    private func toggleDebugPanelMode() {
        isDebugPanelModeEnabled.toggle()
        debugControlPanelView.isHidden = !isDebugPanelModeEnabled
        setMouseCapture(enabled: !isDebugPanelModeEnabled)
    }

    private func setMouseCapture(enabled: Bool) {
        if enabled {
            CGDisplayHideCursor(CGMainDisplayID())
            CGAssociateMouseAndMouseCursorPosition(0)
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    private func presentRuntimeErrorOnce(_ error: Error) {
        guard !hasPresentedRuntimeError else {
            return
        }

        hasPresentedRuntimeError = true
        gameLoop?.stop()
        NSApp.presentError(error)
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
