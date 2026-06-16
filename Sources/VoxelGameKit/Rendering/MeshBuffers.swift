import Metal

struct MeshBuffers {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(device: MTLDevice, mesh: WorldMesh) throws {
        guard
            let vertexBuffer = device.makeBuffer(
                bytes: mesh.vertices,
                length: MemoryLayout<Vertex>.stride * mesh.vertexCount,
                options: .storageModeShared)
        else {
            throw RendererSetupError.meshBufferUnavailable
        }

        self.vertexBuffer = vertexBuffer
        self.vertexCount = mesh.vertexCount
    }
}
