import Cocoa
import Metal
import QuartzCore
import VoxelGameKit

@MainActor
final class MetalView: NSView {
    private let world = VoxelWorld()
    private let player = PlayerController()
    private let inputController = GameInputController()
    private let device: MTLDevice
    private let renderer: Renderer

    private var lastTime = CFAbsoluteTimeGetCurrent()
    private var renderTimer: Timer?

    private var metalLayer: CAMetalLayer {
        guard let layer = layer as? CAMetalLayer else {
            fatalError("Expected CAMetalLayer backing")
        }
        return layer
    }

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        self.device = device
        self.renderer = Renderer(
            device: device,
            world: world,
            drawableSize: Self.makeDrawableSize(for: frameRect, backingScaleFactor: nil))

        super.init(frame: frameRect)

        wantsLayer = true
        configureMetalLayer()
        startRenderLoop()
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
            renderTimer?.invalidate()
            renderTimer = nil
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
            for: frame, backingScaleFactor: window?.backingScaleFactor)
        metalLayer.drawableSize = drawableSize
        renderer.resize(drawableSize: drawableSize)
    }

    private func startRenderLoop() {
        renderTimer?.invalidate()

        renderTimer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(tickRenderLoop),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(renderTimer!, forMode: .common)
    }

    @objc private func tickRenderLoop() {
        renderFrame()
    }

    private func renderFrame() {
        autoreleasepool {
            let currentTime = CFAbsoluteTimeGetCurrent()
            let dt = Float(min(currentTime - lastTime, 0.05))
            lastTime = currentTime

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
