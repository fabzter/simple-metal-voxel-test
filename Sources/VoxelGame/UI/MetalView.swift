import Cocoa
import Metal
import QuartzCore
import VoxelGameKit

@MainActor
final class MetalView: NSView {
    private let world: VoxelWorld
    private let player: PlayerController
    private let inputController: GameInputController
    private let device: MTLDevice
    private let renderer: Renderer

    private var gameLoop: GameLoop?

    private var metalLayer: CAMetalLayer {
        guard let layer = layer as? CAMetalLayer else {
            fatalError("Expected CAMetalLayer backing")
        }
        return layer
    }

    static func make(frame: NSRect) throws -> MetalView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalViewError.metalUnavailable
        }

        let world = VoxelWorld()
        let player = PlayerController()
        let inputController = GameInputController()
        let drawableSize = makeDrawableSize(for: frame, backingScaleFactor: nil)
        let renderer = try Renderer(device: device, world: world, drawableSize: drawableSize)

        return MetalView(
            configuredFrame: frame,
            world: world,
            player: player,
            inputController: inputController,
            device: device,
            renderer: renderer)
    }

    override init(frame frameRect: NSRect) {
        fatalError("Use MetalView.make(frame:) to build a configured MetalView")
    }

    private init(
        configuredFrame frameRect: NSRect,
        world: VoxelWorld,
        player: PlayerController,
        inputController: GameInputController,
        device: MTLDevice,
        renderer: Renderer
    ) {
        self.world = world
        self.player = player
        self.inputController = inputController
        self.device = device
        self.renderer = renderer

        super.init(frame: frameRect)

        wantsLayer = true
        configureMetalLayer()

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
            player.rotateCamera(deltaX: lookDelta.x, deltaY: lookDelta.y)
            player.update(dt: dt, input: inputController.currentInput, in: world)
            renderer.render(into: metalLayer, camera: player.camera)
        }
    }

    private static func makeDrawableSize(for frame: NSRect, backingScaleFactor: CGFloat?) -> CGSize
    {
        let scale = backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return CGSize(width: frame.width * scale, height: frame.height * scale)
    }
}

enum MetalViewError: LocalizedError {
    case metalUnavailable

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is not supported on this device."
        }
    }
}
