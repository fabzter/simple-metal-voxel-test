import AppKit

@MainActor
final class HelpOverlayView: NSVisualEffectView {
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        let titleLabel = NSTextField(labelWithString: "Controls")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        subtitleLabel.maximumNumberOfLines = 0

        let leftColumn = makeColumn(
            title: "Movement",
            rows: [
                ("Move", "W / A / S / D"),
                ("Look", "Mouse"),
                ("Jump", "Space"),
                ("Sprint", "Shift (hold)"),
                ("Fly", "F · Space up · Shift down"),
                ("Mouse", "Esc releases / recaptures"),
            ])
        let middleColumn = makeColumn(
            title: "Build",
            rows: [
                ("Remove", "Left click"),
                ("Place", "Right click"),
                ("Block", "1–8 or scroll"),
                ("Material view", "M"),
            ])
        let rightColumn = makeColumn(
            title: "Interface",
            rows: [
                ("Inspector", "Tab or ⌥⌘I"),
                ("HUD", "F1 or ⌥⌘H"),
                ("Minimap", "⌥⌘M"),
                ("Crosshair", "⌥⌘C"),
                ("This card", "⌘?"),
                ("Quit", "⌘Q"),
            ])

        let columns = NSStackView(views: [leftColumn, middleColumn, rightColumn])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 18

        let footerLabel = NSTextField(
            wrappingLabelWithString:
                "Your world saves automatically when you quit. File: new worlds, seeds, open and save-as. Game: fly toggle, Copy World Seed, sound effects. Sensitivity and field-of-view live in the inspector (Tab)."
        )
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        footerLabel.maximumNumberOfLines = 0

        let stack = NSStackView(views: [titleLabel, subtitleLabel, columns, footerLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 480),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(mouseCaptured: Bool) {
        subtitleLabel.stringValue =
            mouseCaptured
            ? "Mouse look is captured — Esc releases the cursor, ⌘? hides this card."
            : "The cursor is free — press Esc or click the world to recapture."
    }

    private func makeColumn(title: String, rows: [(String, String)]) -> NSStackView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .white

        let grid = NSGridView(
            views: rows.map { row in
                let action = NSTextField(labelWithString: row.0)
                action.font = .systemFont(ofSize: 11, weight: .medium)
                action.textColor = NSColor.white.withAlphaComponent(0.86)

                let input = NSTextField(labelWithString: row.1)
                input.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                input.textColor = NSColor.white.withAlphaComponent(0.92)

                return [action, input]
            })
        grid.rowSpacing = 4
        grid.columnSpacing = 10
        grid.xPlacement = .leading

        let stack = NSStackView(views: [header, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }
}
