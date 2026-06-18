import AppKit

@MainActor
final class DebugHUDView: NSVisualEffectView {
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let perfLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        shortcutLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutLabel.textColor = NSColor.white.withAlphaComponent(0.82)

        [targetLabel, statusLabel, perfLabel].forEach {
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            $0.textColor = .white
            $0.lineBreakMode = .byTruncatingTail
            $0.maximumNumberOfLines = 1
        }

        perfLabel.textColor = NSColor.white.withAlphaComponent(0.86)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        [shortcutLabel, targetLabel, statusLabel, perfLabel].forEach(stack.addArrangedSubview(_:))
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: DebugHUDSnapshot) {
        shortcutLabel.stringValue = "Tab Debug  ·  F1 HUD  ·  1–5 Block"
        targetLabel.stringValue = "Target  \(snapshot.targetCellDescription)"
        let renderMode =
            snapshot.materialDebugMode == "Textured + flat-color"
            ? "Standard view"
            : snapshot.materialDebugMode
        let tintMode =
            snapshot.lodTintOverlayMode == "LOD tint off"
            ? nil
            : snapshot.lodTintOverlayMode
        statusLabel.stringValue =
            ["Place  \(snapshot.selectedPlacementMaterial)", renderMode, tintMode]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
        perfLabel.stringValue =
            "\(format(snapshot.framesPerSecond)) FPS  ·  \(snapshot.visibleChunkCount) chunks  ·  \(snapshot.lodDistribution.isEmpty ? "LOD none" : snapshot.lodDistribution)"
    }

    private func format(_ value: Float) -> String {
        String(format: "%.0f", value)
    }
}
