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
    let yaw: Float
    let cells: [Cell]

    init(scene: GameScene, radius: Int = 8) {
        self.radius = radius
        self.yaw = scene.player.cameraYaw

        let playerCell = Self.cell(for: scene.player.position)
        var collectedCells: [Cell] = []

        for dz in (-radius)...radius {
            for dx in (-radius)...radius {
                let worldX = playerCell.x + dx
                let worldZ = playerCell.z + dz

                if let topY = scene.world.topSolidY(
                    inColumnX: worldX,
                    z: worldZ,
                    withinYRange: 0...(scene.world.gridSize - 1))
                {
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
}
