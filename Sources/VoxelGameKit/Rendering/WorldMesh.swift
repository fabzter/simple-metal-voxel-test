import simd

struct WorldMesh {
    let vertices: [Vertex]

    var vertexCount: Int {
        vertices.count
    }
}
