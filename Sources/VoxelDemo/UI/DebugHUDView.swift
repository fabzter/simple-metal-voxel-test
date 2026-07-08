import AppKit

@MainActor
final class DebugHUDView: NSVisualEffectView {
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        primaryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        primaryLabel.textColor = .white
        primaryLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.maximumNumberOfLines = 1

        secondaryLabel.font = .systemFont(ofSize: 11, weight: .regular)
        secondaryLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        secondaryLabel.lineBreakMode = .byWordWrapping
        secondaryLabel.maximumNumberOfLines = 2

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        [primaryLabel, secondaryLabel].forEach(stack.addArrangedSubview(_:))
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(snapshot: DebugHUDSnapshot) {
        primaryLabel.stringValue = "Block  \(snapshot.selectedPlacementMaterial)  ·  Keys 1–5"

        var secondaryParts: [String] = []
        if let targetMaterial = snapshot.targetMaterial {
            var targetSummary = "Target  \(targetMaterial)"
            if let face = snapshot.targetFace {
                targetSummary += " · \(face)"
            }
            if let distance = snapshot.targetDistanceMeters {
                targetSummary += " · \(format(distance))m"
            }
            secondaryParts.append(targetSummary)
            secondaryParts.append("Left click removes · Right click places")
        } else {
            secondaryParts.append("Aim at a block · Left click removes · Right click places")
        }

        var modeParts: [String] = []
        if snapshot.materialDebugMode != "Textured + flat-color" {
            modeParts.append(snapshot.materialDebugMode)
        }
        if snapshot.lodTintOverlayMode != "LOD tint off" {
            modeParts.append(snapshot.lodTintOverlayMode)
        }
        if !modeParts.isEmpty {
            secondaryParts.append(modeParts.joined(separator: " · "))
        }

        secondaryLabel.stringValue = secondaryParts.joined(separator: "    ")
        secondaryLabel.isHidden = secondaryParts.isEmpty
    }

    private func format(_ value: Float) -> String {
        String(format: "%.1f", value)
    }
}
