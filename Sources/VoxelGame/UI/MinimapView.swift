import AppKit

@MainActor
final class MinimapView: NSView {
    private var snapshot: MinimapSnapshot?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 80
        layer?.masksToBounds = true
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

        let insetBounds = bounds.insetBy(dx: 2, dy: 2)
        let clipPath = NSBezierPath(ovalIn: insetBounds)
        clipPath.addClip()

        NSColor.black.withAlphaComponent(0.45).setFill()
        clipPath.fill()

        guard let snapshot else {
            return
        }

        let cellSize = insetBounds.width / CGFloat(snapshot.radius * 2 + 1)
        for cell in snapshot.cells {
            let x = insetBounds.minX + CGFloat(cell.dx + snapshot.radius) * cellSize
            let y = insetBounds.minY + CGFloat(snapshot.radius - cell.dz) * cellSize
            let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

            color(forTopY: cell.topY).setFill()
            rect.fill()
        }

        let playerRect = NSRect(
            x: insetBounds.minX + CGFloat(snapshot.radius) * cellSize + cellSize * 0.25,
            y: insetBounds.minY + CGFloat(snapshot.radius) * cellSize + cellSize * 0.25,
            width: cellSize * 0.5,
            height: cellSize * 0.5)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: playerRect).fill()

        drawFacingIndicator(cellSize: cellSize, yaw: snapshot.yaw)
        drawNorthMarker(in: insetBounds)
        drawBorder(in: insetBounds)
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

    private func drawFacingIndicator(cellSize: CGFloat, yaw: Float) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let direction = CGVector(dx: CGFloat(sin(yaw)), dy: CGFloat(cos(yaw)))
        let tip = CGPoint(
            x: center.x + direction.dx * cellSize * 1.8,
            y: center.y + direction.dy * cellSize * 1.8)
        let wing = CGVector(dx: -direction.dy, dy: direction.dx)

        let path = NSBezierPath()
        path.lineWidth = 2.5
        path.move(to: center)
        path.line(to: tip)
        path.move(to: tip)
        path.line(
            to: CGPoint(
                x: tip.x - direction.dx * cellSize * 0.7 + wing.dx * cellSize * 0.45,
                y: tip.y - direction.dy * cellSize * 0.7 + wing.dy * cellSize * 0.45))
        path.move(to: tip)
        path.line(
            to: CGPoint(
                x: tip.x - direction.dx * cellSize * 0.7 - wing.dx * cellSize * 0.45,
                y: tip.y - direction.dy * cellSize * 0.7 - wing.dy * cellSize * 0.45))
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }

    private func drawNorthMarker(in rect: NSRect) {
        let label = "N" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.82),
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 6),
            withAttributes: attributes)
    }

    private func drawBorder(in rect: NSRect) {
        let border = NSBezierPath(ovalIn: rect)
        border.lineWidth = 2
        NSColor.white.withAlphaComponent(0.16).setStroke()
        border.stroke()
    }
}
