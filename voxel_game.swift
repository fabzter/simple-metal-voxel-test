import Cocoa
import CoreGraphics
import Metal
import simd

// This demo keeps the shader source inline so the whole project stays in one file.
// Metal compiles this string at startup and turns the two entry points below into
// the vertex and fragment stages of the render pipeline.
//
// High-level flow:
// 1. The CPU generates a big vertex buffer containing only the visible faces of the voxel terrain.
// 2. Each frame the CPU updates the camera matrices in `Uniforms`.
// 3. The vertex shader transforms each voxel vertex from world space into clip space.
// 4. The fragment shader writes the lit color into the current drawable texture.
//
// The `[[attribute(n)]]` annotations must match the vertex descriptor configured in Swift.
// The `[[buffer(1)]]` annotation must match the buffer index used in `render()`.
// MARK: - Metal Shading Language (MSL) Source
let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // Per-vertex data coming from the CPU-side `Vertex` struct.
    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float3 color [[attribute(2)]];
    };

    // Data passed from the vertex stage to the fragment stage.
    struct VertexOut {
        float4 position [[position]];
        float3 color;
    };

    // Per-frame camera data uploaded by the CPU.
    struct Uniforms {
        float4x4 projection;
        float4x4 view;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(1)]]) {
        VertexOut out;

        // Project from world space into clip space.
        out.position = uniforms.projection * uniforms.view * float4(in.position, 1.0);

        // Apply a tiny amount of baked directional lighting so cube faces read clearly.
        // `max(..., 0.2)` keeps faces from going fully black.
        float3 lightDir = normalize(float3(0.5, -1.0, 0.2));
        float diff = max(dot(in.normal, -lightDir), 0.2);
        out.color = in.color * diff;

        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        // The fragment shader just outputs the interpolated lit color.
        return float4(in.color, 1.0);
    }
    """

// One vertex for one triangle corner.
// Position is in world space, normal is per-face for flat lighting, and color is a
// simple terrain tint chosen on the CPU.
// MARK: - Data Structures
struct Vertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD3<Float>
}

// Per-frame data shared by all vertices in the draw call.
// `projection` handles perspective and `view` handles camera orientation/position.
struct Uniforms {
    var projection: float4x4
    var view: float4x4
}

// Small helpers for building the camera matrices used by the shader.
// These are intentionally simple and explicit so the math stays visible in the demo.
// MARK: - SIMD Math Extensions
extension float4x4 {
    // Rotation around the X axis. Used for camera pitch.
    init(rotationX: Float) {
        let c = cos(rotationX)
        let s = sin(rotationX)
        self.init(
            columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0),
                SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)
            ))
    }

    // Rotation around the Y axis. Used for camera yaw.
    init(rotationY: Float) {
        let c = cos(rotationY)
        let s = sin(rotationY)
        self.init(
            columns: (
                SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0),
                SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)
            ))
    }

    // Translation matrix. In the view matrix we translate by `-cameraPos` so the world
    // moves opposite to the camera.
    init(translation t: SIMD3<Float>) {
        self.init(
            columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(t.x, t.y, t.z, 1)
            ))
    }

    // Builds a perspective projection matrix for the vertex shader.
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

// `MetalView` owns almost all demo state:
// - Metal objects needed for drawing.
// - The voxel occupancy grid and generated mesh.
// - The simple player physics state.
// - Input state and the background render loop.
// MARK: - Metal View
class MetalView: NSView {
    // Core Metal objects.
    var metalLayer: CAMetalLayer!
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!

    // GPU resources reused every frame.
    var vertexBuffer: MTLBuffer!
    var uniformsBuffer: MTLBuffer!
    var vertexCount: Int = 0
    var depthTexture: MTLTexture!

    // The world is a fixed-size 3D occupancy grid.
    // `solidGrid` answers: “is there a block at this integer cell?”
    let gridSize = 64
    var solidGrid: [Bool] = []

    // Simple capsule-ish player state. `playerPos` is the bottom-center of the player.
    var playerPos = SIMD3<Float>(32, 45, 32)
    var velocity = SIMD3<Float>(0, 0, 0)
    var isGrounded = false

    // Physics tuning values.
    let gravity: Float = -25.0
    let jumpSpeed: Float = 9.0
    let moveSpeed: Float = 6.0
    let playerHeight: Float = 1.8
    let playerRadius: Float = 0.3

    // First-person camera orientation.
    var cameraYaw: Float = 0.0
    var cameraPitch: Float = -0.2

    // A tiny keyboard state table indexed by macOS virtual key code.
    var keyState = [Bool](repeating: false, count: 256)
    var lastTime = CFAbsoluteTimeGetCurrent()
    var isRunning = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true

        // Render directly into a CAMetalLayer so Metal can present frames to the window.
        let layer = CAMetalLayer()
        self.layer = layer
        self.metalLayer = layer

        // Grab the system default GPU device.
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.metalLayer.device = device
        self.metalLayer.pixelFormat = .bgra8Unorm

        // `framebufferOnly` lets Metal optimize the drawable texture because we only render to it.
        self.metalLayer.framebufferOnly = true

        // `drawableSize` is in physical pixels, not points, so we scale by the display backing factor.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.metalLayer.drawableSize = CGSize(
            width: frame.width * scale, height: frame.height * scale)

        // Command buffers are created from the queue every frame.
        self.commandQueue = device.makeCommandQueue()

        // Build everything the demo needs once at startup.
        setupShaders()
        buildMesh()
        setupDepthTexture()
        startRenderLoop()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Tell AppKit that this view wants a layer-backed implementation, and accept keyboard focus
    // so WASD / space events actually arrive here.
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override var acceptsFirstResponder: Bool { true }

    // Keep the Metal drawable and depth buffer in sync with window resizes.
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
        // Compile the inline MSL source into a shader library.
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            fatalError("Shader compilation failed")
        }

        // Describe how one `Vertex` is laid out in memory.
        // These offsets must match the field order in the Swift `Vertex` struct and the shader's
        // `[[attribute(n)]]` indices.
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

        // The pipeline state bundles the fixed render configuration and the shader entry points.
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "fragment_main")
        pipelineDesc.vertexDescriptor = vertexDesc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDesc.depthAttachmentPixelFormat = .depth32Float

        pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)

        // Enable standard depth testing so nearer voxel faces hide farther ones.
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }

    // Returns whether a given grid cell contains a solid block.
    // Cells below the world count as solid so the player cannot fall forever.
    // Cells outside the horizontal bounds count as empty so edge faces still render.
    func isSolid(x: Int, y: Int, z: Int) -> Bool {
        if y < 0 { return true }
        if x < 0 || x >= gridSize || y >= gridSize || z < 0 || z >= gridSize { return false }
        return solidGrid[x + y * gridSize + z * gridSize * gridSize]
    }

    // Checks the player against the world by turning the player's cylinder-like body into a
    // voxel-space AABB. If any overlapped cell is solid, we treat it as a collision.
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
        // Reset the occupancy grid.
        solidGrid = [Bool](repeating: false, count: gridSize * gridSize * gridSize)

        // Generate a simple height field using sine/cosine waves.
        // Each (x, z) column is filled from y=0 up to `maxY`.
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

        // The final render mesh is just a flat array of triangle vertices.
        // We do not keep index buffers or per-block objects in this demo.
        var meshVertices: [Vertex] = []

        // Adds one cube face as two triangles.
        func addFace(offset: SIMD3<Float>, faceIndex: Int, color: SIMD3<Float>) {
            // Each face is defined around the origin, then translated by `offset` into world space.
            // The points are listed in counter-clockwise order when viewed from outside the cube,
            // which gives them outward-facing normals for standard front-face rasterization.
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

            // Turn the quad into two triangles.
            meshVertices.append(Vertex(position: v0, normal: normal, color: color))
            meshVertices.append(Vertex(position: v1, normal: normal, color: color))
            meshVertices.append(Vertex(position: v2, normal: normal, color: color))

            meshVertices.append(Vertex(position: v0, normal: normal, color: color))
            meshVertices.append(Vertex(position: v2, normal: normal, color: color))
            meshVertices.append(Vertex(position: v3, normal: normal, color: color))
        }

        // Visit every occupied cell and emit only the faces that touch air.
        // This is the classic "hidden face culling" optimization for voxel terrain generation.
        for x in 0..<gridSize {
            for y in 0..<gridSize {
                for z in 0..<gridSize {
                    if isSolid(x: x, y: y, z: z) {
                        let pos = SIMD3<Float>(Float(x), Float(y), Float(z))

                        // Give higher terrain greener colors and lower terrain rockier colors.
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

        // Shared storage keeps the buffers CPU-accessible. That is convenient for this simple demo
        // because we build the mesh and rewrite the uniform block directly from Swift.
        let options = MTLResourceOptions.storageModeShared
        vertexBuffer = device.makeBuffer(
            bytes: meshVertices, length: MemoryLayout<Vertex>.stride * meshVertices.count,
            options: options)
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: options)
    }

    func setupDepthTexture() {
        let size = metalLayer.drawableSize
        guard size.width > 0 && size.height > 0 else { return }

        // The depth texture must match the drawable size because every frame uses it as the depth
        // render target alongside the current color attachment.
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MTLPixelFormat.depth32Float, width: Int(size.width),
            height: Int(size.height), mipmapped: false)
        desc.usage = MTLTextureUsage.renderTarget
        desc.storageMode = MTLStorageMode.private
        depthTexture = device.makeTexture(descriptor: desc)
    }

    // MARK: - Game Loop

    func startRenderLoop() {
        // The demo drives its own fixed-ish render thread instead of using MTKView.
        // That keeps the Metal wiring visible, which matches the single-file teaching goal.
        let renderQueue = DispatchQueue(label: "render", qos: .userInteractive)
        renderQueue.async { [weak self] in
            while self?.isRunning == true {
                self?.render()
                Thread.sleep(forTimeInterval: 1.0 / 60.0)
            }
        }
    }

    func updatePhysics(dt: Float) {
        // Gravity only applies while airborne.
        if !isGrounded {
            velocity.y += gravity * dt
        }

        // Convert WASD input into a movement vector relative to the camera's yaw.
        var inputVel = SIMD3<Float>(0, 0, 0)
        let forward = SIMD3<Float>(sin(cameraYaw), 0, -cos(cameraYaw))
        let right = SIMD3<Float>(cos(cameraYaw), 0, sin(cameraYaw))

        // macOS key codes: W=13, S=1, A=0, D=2.
        if keyState[13] { inputVel += forward }
        if keyState[1] { inputVel -= forward }
        if keyState[0] { inputVel -= right }
        if keyState[2] { inputVel += right }

        // Normalize diagonal movement so it is not faster than straight-line movement.
        if length(inputVel) > 0 {
            inputVel = normalize(inputVel) * moveSpeed
        }

        velocity.x = inputVel.x
        velocity.z = inputVel.z

        // macOS key code 49 is Space.
        if keyState[49] && isGrounded {
            velocity.y = jumpSpeed
            isGrounded = false
        }

        // Resolve movement axis-by-axis. This is simple and stable for voxel collision.
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
                // Falling into the ground: snap the player to the top of the touched voxel.
                isGrounded = true
                let minY = Int(floor(testPosY.y))
                testPosY.y = Float(minY + 1)
            } else {
                // Jumping into a ceiling: place the player just below it.
                let maxY = Int(floor(testPosY.y + playerHeight))
                testPosY.y = Float(maxY) - playerHeight - 0.001
            }
            velocity.y = 0
        }

        playerPos = testPosY
    }

    func render() {
        autoreleasepool {
            // `nextDrawable()` gives us the current screen-backed texture to render into.
            // If a drawable or command buffer is unavailable we skip the frame.
            guard let drawable = metalLayer.nextDrawable(),
                let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            let currentTime = CFAbsoluteTimeGetCurrent()

            // Clamp the frame delta so large pauses do not explode the physics simulation.
            let dt = Float(min(currentTime - lastTime, 0.05))
            lastTime = currentTime

            updatePhysics(dt: dt)

            // Put the camera roughly at eye height above the player's feet.
            let cameraPos = playerPos + SIMD3<Float>(0, 1.6, 0)

            let aspect = Float(metalLayer.drawableSize.width / metalLayer.drawableSize.height)
            guard aspect > 0 else { return }

            let projection = float4x4.perspective(
                fov: 65.0 * (.pi / 180.0), aspect: aspect, near: 0.1, far: 1000.0)

            // The view matrix is rotation first, then translation into camera-relative space.
            let view =
                float4x4(rotationX: cameraPitch) * float4x4(rotationY: cameraYaw)
                * float4x4(translation: -cameraPos)
            var uniforms = Uniforms(projection: projection, view: view)

            // Upload the latest camera matrices for this frame.
            memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

            // Describe the render targets used by this draw pass.
            // Color clears to a sky-blue background; depth clears to the farthest possible value.
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

            // Bind the pipeline and the two vertex-stage buffers declared in the shader.
            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)

            // Draw the whole world as one big triangle list.
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)

            encoder.endEncoding()

            // Schedule presentation of the drawable after GPU execution finishes.
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
            // Mouse motion directly steers the first-person camera.
            cameraYaw += Float(event.deltaX) * 0.005
            cameraPitch += Float(event.deltaY) * 0.005

            // Clamp pitch so the camera never flips upside down.
            if cameraPitch > 1.5 { cameraPitch = 1.5 }
            if cameraPitch < -1.5 { cameraPitch = -1.5 }
        }
    }
}

// App setup is intentionally minimal: make a window, install the Metal view, then forward
// keyboard and mouse events into the demo.
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

        // Hide and decouple the system cursor so mouse motion feels like a classic FPS camera.
        CGDisplayHideCursor(CGMainDisplayID())
        CGAssociateMouseAndMouseCursorPosition(0)

        // Route local input events into `MetalView`.
        // Escape (key code 53) exits the app.
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .mouseMoved]) { event in
            if event.type == .keyDown && event.keyCode == 53 {
                NSApp.terminate(nil)
            }
            self.metalView.handleEvent(event)
            return event
        }
    }
}

// Standard Cocoa app bootstrap.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
