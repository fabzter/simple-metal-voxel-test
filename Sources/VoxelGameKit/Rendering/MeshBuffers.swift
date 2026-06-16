import Metal

struct MeshBuffers {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int

    init(device: MTLDevice, mesh: WorldMesh) {
        guard
            let vertexBuffer = device.makeBuffer(
                bytes: mesh.vertices,
                length: MemoryLayout<Vertex>.stride * mesh.vertexCount,
                options: .storageModeShared)
        else {
            fatalError("Failed to allocate vertex buffer")
        }

        self.vertexBuffer = vertexBuffer
        self.vertexCount = mesh.vertexCount
    }
}
