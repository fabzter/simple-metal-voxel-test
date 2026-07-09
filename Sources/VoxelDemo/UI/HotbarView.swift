import AppKit
import VoxelEngine

/// The block palette shown at the bottom of the screen — the piece that makes selecting
/// what you build feel like a game rather than a debug toggle.
///
/// The demo owns this presentation, but the *content* comes from the engine: one slot per
/// `BlockMaterialType`, each colored by the material's reusable `swatchColor`. Selection is
/// driven from the outside (number keys 1–N or the scroll wheel), so this view is purely a
/// display of the current choice.
@MainActor
final class HotbarView: NSView {
    private let materials = BlockMaterialType.allCases
    private var slots: [SlotView] = []
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        for (index, material) in materials.enumerated() {
            let slot = SlotView(material: material, number: index + 1)
            slots.append(slot)
            row.addArrangedSubview(slot)
        }

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        // A soft shadow keeps the label readable over bright sky or terrain.
        nameLabel.wantsLayer = true
        nameLabel.shadow = Self.textShadow

        let column = NSStackView(views: [row, nameLabel])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 4
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Overlay only — never intercept clicks meant for the game (place/remove blocks).
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(selected: BlockMaterialType) {
        for (index, material) in materials.enumerated() {
            slots[index].setSelected(material == selected)
        }
        nameLabel.stringValue = selected.displayName
    }

    private static let textShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }()
}

/// One palette slot: a rounded color swatch with its number in the corner. Highlights
/// with a bright ring when it is the active selection.
@MainActor
private final class SlotView: NSView {
    private static let size: CGFloat = 46

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    convenience init(material: BlockMaterialType, number: Int) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        let c = material.swatchColor
        layer?.backgroundColor =
            NSColor(
                srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1
            ).cgColor

        let numberLabel = NSTextField(labelWithString: "\(number)")
        numberLabel.font = .systemFont(ofSize: 11, weight: .bold)
        numberLabel.textColor = .white
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 2
        numberLabel.shadow = shadow
        addSubview(numberLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            numberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
        ])

        setSelected(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        guard let layer else { return }
        if selected {
            layer.borderColor = NSColor.white.cgColor
            layer.borderWidth = 3
            alphaValue = 1
        } else {
            layer.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
            layer.borderWidth = 1
            alphaValue = 0.82
        }
    }
}
