import Foundation
import VoxelGameKit
import simd

struct MinimapSnapshot {
    struct Cell {
        let dx: Int
        let dz: Int
        let topY: Int
    }

    let radius: Int
    let cells: [Cell]

    init(scene: GameScene, radius: Int = 6) {
        self.radius = radius

        let playerCell = Self.cell(for: scene.player.position)
        var collectedCells: [Cell] = []

        for dz in (-radius)...radius {
            for dx in (-radius)...radius {
                let worldX = playerCell.x + dx
                let worldZ = playerCell.z + dz

                if let topY = Self.topSolidY(in: scene.world, x: worldX, z: worldZ) {
                    collectedCells.append(Cell(dx: dx, dz: dz, topY: topY))
                }
            }
        }

        cells = collectedCells
    }

    private static func cell(for point: SIMD3<Float>) -> (x: Int, z: Int) {
        (
            x: Int(floor(point.x + 0.5)),
            z: Int(floor(point.z + 0.5))
        )
    }

    private static func topSolidY(in world: VoxelWorld, x: Int, z: Int) -> Int? {
        for y in stride(from: world.gridSize - 1, through: 0, by: -1) {
            if world.isSolid(x: x, y: y, z: z) {
                return y
            }
        }

        return nil
    }
}
