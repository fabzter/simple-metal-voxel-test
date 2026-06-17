import AppKit

@MainActor
final class MinimapView: NSView {
    private var snapshot: MinimapSnapshot?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    func update(snapshot: MinimapSnapshot) {
        self.snapshot = snapshot
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.55).setFill()
        dirtyRect.fill()

        guard let snapshot else {
            return
        }

        let cellSize = bounds.width / CGFloat(snapshot.radius * 2 + 1)
        for cell in snapshot.cells {
            let x = CGFloat(cell.dx + snapshot.radius) * cellSize
            let y = CGFloat(snapshot.radius - cell.dz) * cellSize
            let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

            color(forTopY: cell.topY).setFill()
            rect.fill()
        }

        let playerRect = NSRect(
            x: CGFloat(snapshot.radius) * cellSize + cellSize * 0.25,
            y: CGFloat(snapshot.radius) * cellSize + cellSize * 0.25,
            width: cellSize * 0.5,
            height: cellSize * 0.5)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: playerRect).fill()
    }

    private func color(forTopY topY: Int) -> NSColor {
        if topY >= 22 {
            return NSColor(calibratedRed: 0.92, green: 0.92, blue: 0.98, alpha: 0.95)
        }
        if topY >= 14 {
            return NSColor(calibratedRed: 0.30, green: 0.70, blue: 0.25, alpha: 0.95)
        }
        if topY >= 10 {
            return NSColor(calibratedRed: 0.36, green: 0.55, blue: 0.36, alpha: 0.95)
        }
        return NSColor(calibratedWhite: 0.55, alpha: 0.95)
    }
}
