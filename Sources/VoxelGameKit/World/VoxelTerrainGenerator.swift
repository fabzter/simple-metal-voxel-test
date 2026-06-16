import simd

struct VoxelTerrainGenerator {
    func populate(_ world: VoxelWorld) {
        for x in 0..<world.gridSize {
            for z in 0..<world.gridSize {
                let height = sin(Float(x) * 0.2) * 4.0 + cos(Float(z) * 0.2) * 3.0
                let maxY = Int(height) + 15

                for y in 0...maxY where y >= 0 && y < world.gridSize {
                    world.setSolid(true, x: x, y: y, z: z)
                }
            }
        }
    }
}
