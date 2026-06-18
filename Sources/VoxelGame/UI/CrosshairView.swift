import AppKit
import VoxelGameKit

@MainActor
final class CrosshairView: NSView {
    private var hasTarget = false
    private var editFeedback: EditFeedback?

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

    func update(hasTarget: Bool, editFeedback: EditFeedback?) {
        guard
            self.hasTarget != hasTarget
                || self.editFeedback?.remainingTime != editFeedback?.remainingTime
                || self.editFeedback?.kind != editFeedback?.kind
        else {
            return
        }

        self.hasTarget = hasTarget
        self.editFeedback = editFeedback
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if hasTarget {
            let ringRect = NSRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 1.5
            NSColor.systemYellow.withAlphaComponent(0.45).setStroke()
            ring.stroke()
        }

        let crosshair = NSBezierPath()
        crosshair.lineWidth = 2
        crosshair.move(to: CGPoint(x: center.x - 7, y: center.y))
        crosshair.line(to: CGPoint(x: center.x + 7, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 7))
        crosshair.line(to: CGPoint(x: center.x, y: center.y + 7))

        let color = hasTarget ? NSColor.systemYellow : NSColor.white
        color.withAlphaComponent(0.96).setStroke()
        crosshair.stroke()

        if let editFeedback {
            let pulse = CGFloat(max(0, min(1, editFeedback.remainingTime / 0.18)))
            let radius = 11 + (1 - pulse) * 8
            let feedbackRect = NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2)
            let feedbackPath = NSBezierPath(ovalIn: feedbackRect)
            feedbackPath.lineWidth = 2

            let feedbackColor: NSColor
            switch editFeedback.kind {
            case .remove:
                feedbackColor = NSColor.systemRed
            case .place:
                feedbackColor = NSColor.systemGreen
            }

            feedbackColor.withAlphaComponent(0.30 + pulse * 0.45).setStroke()
            feedbackPath.stroke()
        }
    }
}
