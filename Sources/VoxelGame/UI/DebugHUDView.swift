import AppKit

// A small translucent overlay that explains the controls and shows live camera/world data.
// It is intentionally simple AppKit UI so a beginner can inspect it without learning a full UI
// framework first.
@MainActor
final class DebugHUDView: NSVisualEffectView {
    private let label = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.maximumNumberOfLines = 0
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 420),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: DebugHUDSnapshot) {
        let seedLine: String
        if let worldSeed = snapshot.worldSeed {
            seedLine = "Seed: \(worldSeed)"
        } else {
            seedLine = "Seed: n/a"
        }

        label.stringValue = """
            Controls
            W/A/S/D        Move
            Mouse          Look
            Space          Jump
            Left click     Remove block
            Right click    Place block
            Tab            Toggle debug panel
            M              Toggle material debug
            F1             Toggle HUD
            1-5            Select block type
            1 Grass · 2 Dirt · 3 Stone · 4 Moss · 5 Snow
            Esc            Quit

            Camera
            Position: x=\(format(snapshot.cameraPosition.x)) y=\(format(snapshot.cameraPosition.y)) z=\(format(snapshot.cameraPosition.z))
            Yaw:      \(format(snapshot.yawDegrees))°
            Pitch:    \(format(snapshot.pitchDegrees))°
            Target:   \(snapshot.targetCellDescription)

            World
            \(seedLine)
            Mesh revision: \(snapshot.meshRevision)
            Vertices:      \(snapshot.vertexCount)
            Visible chunks:\(snapshot.visibleChunkCount)
            LOD rings:     \(snapshot.lodDistribution.isEmpty ? "none" : snapshot.lodDistribution)
            Materials:     \(snapshot.materialDebugMode)
            LOD tint:      \(snapshot.lodTintOverlayMode)
            Place block:   \(snapshot.selectedPlacementMaterial)

            Performance
            Frame time:    \(format(snapshot.frameTimeMilliseconds)) ms
            FPS:           \(format(snapshot.framesPerSecond))
            """
    }

    private func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}
