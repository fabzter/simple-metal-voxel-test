import Metal

struct MeshBuffers {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(device: MTLDevice, mesh: WorldMesh) throws {
        let vertexCount = mesh.vertexCount
        let bufferLength = max(MemoryLayout<Vertex>.stride * max(vertexCount, 1), 1)

        let vertexBuffer: MTLBuffer?
        if vertexCount > 0 {
            vertexBuffer = device.makeBuffer(
                bytes: mesh.vertices,
                length: bufferLength,
                options: .storageModeShared)
        } else {
            vertexBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared)
        }

        guard let vertexBuffer else {
            throw RendererSetupError.meshBufferUnavailable
        }

        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertexCount
    }
}
