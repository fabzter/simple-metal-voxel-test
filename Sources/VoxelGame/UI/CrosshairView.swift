import AppKit

@MainActor
final class CrosshairView: NSView {
    private var hasTarget = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    func update(hasTarget: Bool) {
        guard self.hasTarget != hasTarget else {
            return
        }

        self.hasTarget = hasTarget
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: CGPoint(x: center.x - 8, y: center.y))
        path.line(to: CGPoint(x: center.x + 8, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - 8))
        path.line(to: CGPoint(x: center.x, y: center.y + 8))

        let color = hasTarget ? NSColor.systemYellow : NSColor.white
        color.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }
}
