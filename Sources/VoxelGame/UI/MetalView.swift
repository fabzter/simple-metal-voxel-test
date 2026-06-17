import Cocoa
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

    private var gameLoop: GameLoop?
    private var hasPresentedRuntimeError = false

    private var metalLayer: CAMetalLayer {
        guard let layer = layer as? CAMetalLayer else {
            fatalError("Expected CAMetalLayer backing")
        }
        return layer
    }

    // Factory entry point used by app startup and tests.
    // `deviceProvider` is injectable so tests can exercise the “no Metal available” path.
    static func make(
        frame: NSRect,
        deviceProvider: () -> MTLDevice? = MTLCreateSystemDefaultDevice
    ) throws -> MetalView {
        guard let device = deviceProvider() else {
            throw MetalViewError.metalUnavailable
        }

        let scene = GameScene()
        let inputController = GameInputController()
        let drawableSize = makeDrawableSize(for: frame, backingScaleFactor: nil)
        let renderer = try Renderer(device: device, world: scene.world, drawableSize: drawableSize)
        let debugHUDView = DebugHUDView(frame: .zero)
        let minimapView = MinimapView(frame: .zero)
        let crosshairView = CrosshairView(frame: .zero)

        return MetalView(
            configuredFrame: frame,
            scene: scene,
            inputController: inputController,
            device: device,
            renderer: renderer,
            debugHUDView: debugHUDView,
            minimapView: minimapView,
            crosshairView: crosshairView)
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
        crosshairView: CrosshairView
    ) {
        self.scene = scene
        self.inputController = inputController
        self.device = device
        self.renderer = renderer
        self.debugHUDView = debugHUDView
        self.minimapView = minimapView
        self.crosshairView = crosshairView

        super.init(frame: frameRect)

        wantsLayer = true
        configureMetalLayer()
        configureOverlayViews()
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
        }

        super.viewWillMove(toWindow: newWindow)
    }

    func handleEvent(_ event: NSEvent) {
        inputController.handle(event)
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
        ])
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
            let lookDelta = inputController.consumeLookDelta()
            let editActions = inputController.consumeEditActions()
            scene.update(
                dt: dt, input: inputController.currentInput, lookDelta: lookDelta,
                editActions: editActions)

            do {
                try renderer.render(into: metalLayer, world: scene.world, camera: scene.camera)
                updateOverlayViews()
            } catch {
                presentRuntimeErrorOnce(error)
            }
        }
    }

    private func updateOverlayViews() {
        debugHUDView.update(snapshot: DebugHUDSnapshot(scene: scene, renderer: renderer))
        minimapView.update(snapshot: MinimapSnapshot(scene: scene))
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
