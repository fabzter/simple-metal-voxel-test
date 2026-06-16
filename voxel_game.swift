import Cocoa
import CoreGraphics
import Metal
import simd

// MARK: - Metal Shading Language (MSL) Source
let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float3 color [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float3 color;
    };

    struct Uniforms {
        float4x4 projection;
        float4x4 view;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(1)]]) {
        VertexOut out;
        out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);

        // Simple directional lighting
        float3 lightDir = normalize(float3(0.5, -1.0, 0.2));
        float diff = max(dot(in.normal, -lightDir), 0.2);
        out.color = in.color * diff;

        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        return float4(in.color, 1.0);
    }
    """

// MARK: - Data Structures
struct Vertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD3<Float>
}

struct Uniforms {
    var projection: float4x4
    var view: float4x4
}

// MARK: - SIMD Math Extensions
extension float4x4 {
    init(rotationX: Float) {
        let c = cos(rotationX)
        let s = sin(rotationX)
        self.init(
            columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0),
                SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)
            ))
    }

    init(rotationY: Float) {
        let c = cos(rotationY)
        let s = sin(rotationY)
        self.init(
            columns: (
                SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0),
                SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)
            ))
    }

    init(translation t: SIMD3<Float>) {
        self.init(
            columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(t.x, t.y, t.z, 1)
            ))
    }

    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let yScale = 1 / tan(fov * 0.5)
        let xScale = yScale / aspect
        let zScale = far / (near - far)
        let wzScale = (near * far) / (near - far)

        return float4x4(
            columns: (
                SIMD4(xScale, 0, 0, 0), SIMD4(0, yScale, 0, 0),
                SIMD4(0, 0, zScale, -1), SIMD4(0, 0, wzScale, 0)
            ))
    }
}

// MARK: - Metal View
class MetalView: NSView {
    var metalLayer: CAMetalLayer!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!

    var vertexBuffer: MTLBuffer!
    var uniformsBuffer: MTLBuffer!
    var vertexCount: Int = 0
    var depthTexture: MTLTexture!

    // Grid & Physics State
    let gridSize = 64
    var solidGrid: [Bool] = []

    var playerPos = SIMD3<Float>(32, 45, 32)
    var velocity = SIMD3<Float>(0, 0, 0)
    var isGrounded = false

    let gravity: Float = -25.0
    let jumpSpeed: Float = 9.0
    let moveSpeed: Float = 6.0
    let playerHeight: Float = 1.8
    let playerRadius: Float = 0.3

    var cameraYaw: Float = 0.0
    var cameraPitch: Float = -0.2

    var keyState = [Bool](repeating: false, count: 256)
    var lastTime = CFAbsoluteTimeGetCurrent()
    var isRunning = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true

        let layer = CAMetalLayer()
        self.layer = layer
        self.metalLayer = layer

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.metalLayer.device = device
        self.metalLayer.pixelFormat = .bgra8Unorm
        self.metalLayer.framebufferOnly = true

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.metalLayer.drawableSize = CGSize(
            width: frame.width * scale, height: frame.height * scale)

        self.commandQueue = device.makeCommandQueue()

        setupShaders()
        buildMesh()
        setupDepthTexture()
        startRenderLoop()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override var acceptsFirstResponder: Bool { true }

    override var frame: NSRect {
        didSet {
            let scale = window?.backingScaleFactor ?? 2.0
            metalLayer.drawableSize = CGSize(
                width: frame.width * scale, height: frame.height * scale)
            setupDepthTexture()
        }
    }

    // MARK: - Setup Logic

    func setupShaders() {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            fatalError("Shader compilation failed")
        }

        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float3
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0

        vertexDesc.attributes[1].format = .float3
        vertexDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDesc.attributes[1].bufferIndex = 0

        vertexDesc.attributes[2].format = .float3
        vertexDesc.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDesc.attributes[2].bufferIndex = 0

        vertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDesc.layouts[0].stepFunction = .perVertex

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        pipelineDesc.vertexDescriptor = vertexDesc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDesc.depthAttachmentPixelFormat = .depth32Float

        pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }

    func isSolid(x: Int, y: Int, z: Int) -> Bool {
        if y < 0 { return true }
        if x < 0 || x >= gridSize || y >= gridSize || z < 0 || z >= gridSize { return false }
        return solidGrid[x + y * gridSize + z * gridSize * gridSize]
    }

    func checkCollision(pos: SIMD3<Float>) -> Bool {
        let minX = Int(floor(pos.x - playerRadius))
        let maxX = Int(floor(pos.x + playerRadius))
        let minY = Int(floor(pos.y))
        let maxY = Int(floor(pos.y + playerHeight))
        let minZ = Int(floor(pos.z - playerRadius))
        let maxZ = Int(floor(pos.z + playerRadius))

        for x in minX...maxX {
            for y in minY...maxY {
                for z in minZ...maxZ {
                    if isSolid(x: x, y: y, z: z) {
                        return true
                    }
                }
            }
        }
        return false
    }

    func buildMesh() {
        solidGrid = [Bool](repeating: false, count: gridSize * gridSize * gridSize)

        for x in 0..<gridSize {
            for z in 0..<gridSize {
                let h = sin(Float(x) * 0.2) * 4.0 + cos(Float(z) * 0.2) * 3.0
                let maxY = Int(h) + 15
                for y in 0...maxY {
                    if y >= 0 && y < gridSize {
                        solidGrid[x + y * gridSize + z * gridSize * gridSize] = true
                    }
                }
            }
        }

        var meshVertices: [Vertex] = []

        func addFace(offset: SIMD3<Float>, faceIndex: Int, color: SIMD3<Float>) {
            // Mathematically corrected Counter-Clockwise winding order for all 6 faces
            let faces: [[SIMD3<Float>]] = [
                [
                    SIMD3(-0.5, -0.5, 0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, 0.5, 0.5),
                    SIMD3(-0.5, 0.5, 0.5),
                ],  // Front (+Z)
                [
                    SIMD3(0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, 0.5, -0.5),
                    SIMD3(0.5, 0.5, -0.5),
                ],  // Back (-Z)
                [
                    SIMD3(-0.5, 0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, 0.5, -0.5),
                    SIMD3(-0.5, 0.5, -0.5),
                ],  // Top (+Y)
                [
                    SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, -0.5, 0.5),
                    SIMD3(-0.5, -0.5, 0.5),
                ],  // Bottom (-Y)
                [
                    SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5),
                    SIMD3(0.5, 0.5, 0.5),
                ],  // Right (+X)
                [
                    SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, 0.5, 0.5),
                    SIMD3(-0.5, 0.5, -0.5),
                ],  // Left (-X)
            ]
            let normals: [SIMD3<Float>] = [
                SIMD3(0, 0, 1), SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(1, 0, 0),
                SIMD3(-1, 0, 0),
            ]

            let quad = faces[faceIndex]
            let normal = normals[faceIndex]

            let v0 = offset + quad[0]
            let v1 = offset + quad[1]
            let v2 = offset + quad[2]
            let v3 = offset + quad[3]

            meshVertices.append(Vertex(position: v0, normal: normal, color: color))
            meshVertices.append(Vertex(position: v1, normal: normal, color: color))
            meshVertices.append(Vertex(position: v2, normal: normal, color: color))

            meshVertices.append(Vertex(position: v0, normal: normal, color: color))
            meshVertices.append(Vertex(position: v2, normal: normal, color: color))
            meshVertices.append(Vertex(position: v3, normal: normal, color: color))
        }

        for x in 0..<gridSize {
            for y in 0..<gridSize {
                for z in 0..<gridSize {
                    if isSolid(x: x, y: y, z: z) {
                        let pos = SIMD3<Float>(Float(x), Float(y), Float(z))

                        var color = SIMD3<Float>(0.4, 0.7, 0.2)
                        if y > 15 {
                            color = SIMD3<Float>(0.2, 0.8, 0.2)
                        } else if y > 12 {
                            color = SIMD3<Float>(0.5, 0.3, 0.1)
                        } else {
                            color = SIMD3<Float>(0.5, 0.5, 0.5)
                        }

                        if !isSolid(x: x, y: y + 1, z: z) {
                            addFace(offset: pos, faceIndex: 2, color: color)
                        }
                        if !isSolid(x: x, y: y - 1, z: z) {
                            addFace(offset: pos, faceIndex: 3, color: color)
                        }
                        if !isSolid(x: x, y: y, z: z + 1) {
                            addFace(offset: pos, faceIndex: 0, color: color)
                        }
                        if !isSolid(x: x, y: y, z: z - 1) {
                            addFace(offset: pos, faceIndex: 1, color: color)
                        }
                        if !isSolid(x: x + 1, y: y, z: z) {
                            addFace(offset: pos, faceIndex: 4, color: color)
                        }
                        if !isSolid(x: x - 1, y: y, z: z) {
                            addFace(offset: pos, faceIndex: 5, color: color)
                        }
                    }
                }
            }
        }

        vertexCount = meshVertices.count
        let options = MTLResourceOptions.storageModeShared
        vertexBuffer = device.makeBuffer(
            bytes: meshVertices, length: MemoryLayout<Vertex>.stride * meshVertices.count,
            options: options)
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: options)
    }

    func setupDepthTexture() {
        let size = metalLayer.drawableSize
        guard size.width > 0 && size.height > 0 else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MTLPixelFormat.depth32Float, width: Int(size.width),
            height: Int(size.height), mipmapped: false)
        desc.usage = MTLTextureUsage.renderTarget
        desc.storageMode = MTLStorageMode.private
        depthTexture = device.makeTexture(descriptor: desc)
    }

    // MARK: - Game Loop

    func startRenderLoop() {
        let renderQueue = DispatchQueue(label: "render", qos: .userInteractive)
        renderQueue.async { [weak self] in
            while self?.isRunning == true {
                self?.render()
                Thread.sleep(forTimeInterval: 1.0 / 60.0)
            }
        }
    }

    func updatePhysics(dt: Float) {
        if !isGrounded {
            velocity.y += gravity * dt
        }

        var inputVel = SIMD3<Float>(0, 0, 0)
        let forward = SIMD3<Float>(sin(cameraYaw), 0, -cos(cameraYaw))
        let right = SIMD3<Float>(cos(cameraYaw), 0, sin(cameraYaw))

        if keyState[13] { inputVel += forward }
        if keyState[1] { inputVel -= forward }
        if keyState[0] { inputVel -= right }
        if keyState[2] { inputVel += right }

        if length(inputVel) > 0 {
            inputVel = normalize(inputVel) * moveSpeed
        }

        velocity.x = inputVel.x
        velocity.z = inputVel.z

        if keyState[49] && isGrounded {
            velocity.y = jumpSpeed
            isGrounded = false
        }

        var newPos = playerPos
        newPos.x += velocity.x * dt
        if checkCollision(pos: newPos) {
            newPos.x = playerPos.x
            velocity.x = 0
        }

        newPos.z += velocity.z * dt
        if checkCollision(pos: newPos) {
            newPos.z = playerPos.z
            velocity.z = 0
        }

        isGrounded = false
        var testPosY = newPos
        testPosY.y += velocity.y * dt

        if checkCollision(pos: testPosY) {
            if velocity.y <= 0 {
                isGrounded = true
                let minY = Int(floor(testPosY.y))
                testPosY.y = Float(minY + 1)
            } else {
                let maxY = Int(floor(testPosY.y + playerHeight))
                testPosY.y = Float(maxY) - playerHeight - 0.001
            }
            velocity.y = 0
        }

        playerPos = testPosY
    }

    func render() {
        autoreleasepool {
            guard let drawable = metalLayer.nextDrawable(),
                let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            let currentTime = CFAbsoluteTimeGetCurrent()
            let dt = Float(min(currentTime - lastTime, 0.05))
            lastTime = currentTime

            updatePhysics(dt: dt)

            let cameraPos = playerPos + SIMD3<Float>(0, 1.6, 0)

            let aspect = Float(metalLayer.drawableSize.width / metalLayer.drawableSize.height)
            guard aspect > 0 else { return }

            let projection = float4x4.perspective(
                fov: 65.0 * (.pi / 180.0), aspect: aspect, near: 0.1, far: 1000.0)

            let view =
                float4x4(rotationX: cameraPitch) * float4x4(rotationY: cameraYaw)
                * float4x4(translation: -cameraPos)
            var uniforms = Uniforms(projection: projection, view: view)

            memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

            let passDesc = MTLRenderPassDescriptor()
            passDesc.colorAttachments[0].texture = drawable.texture
            passDesc.colorAttachments[0].loadAction = .clear
            passDesc.colorAttachments[0].clearColor = MTLClearColor(
                red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0)
            passDesc.depthAttachment.texture = depthTexture
            passDesc.depthAttachment.loadAction = .clear
            passDesc.depthAttachment.clearDepth = 1.0

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
                return
            }

            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    func handleEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            keyState[Int(event.keyCode)] = true
        } else if event.type == .keyUp {
            keyState[Int(event.keyCode)] = false
        } else if event.type == .mouseMoved {
            cameraYaw += Float(event.deltaX) * 0.005
            cameraPitch += Float(event.deltaY) * 0.005
            if cameraPitch > 1.5 { cameraPitch = 1.5 }
            if cameraPitch < -1.5 { cameraPitch = -1.5 }
        }
    }
}

// MARK: - App Entry Point
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var metalView: MetalView!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Physics Voxel Engine"
        window.center()
        window.acceptsMouseMovedEvents = true

        metalView = MetalView(frame: frame)
        window.contentView = metalView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(metalView)

        CGDisplayHideCursor(CGMainDisplayID())
        CGAssociateMouseAndMouseCursorPosition(0)

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .mouseMoved]) { event in
            if event.type == .keyDown && event.keyCode == 53 {
                NSApp.terminate(nil)
            }
            self.metalView.handleEvent(event)
            return event
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
