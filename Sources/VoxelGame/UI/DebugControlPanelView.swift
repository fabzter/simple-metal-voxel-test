import AppKit
import VoxelGameKit

@MainActor
final class DebugControlPanelView: NSVisualEffectView {
    var onMaterialModeChanged: ((MaterialDebugMode) -> Void)?
    var onLODOverlayModeChanged: ((LODTintOverlayMode) -> Void)?
    var onBlockMaterialChanged: ((BlockMaterialType) -> Void)?
    var onFrustumChanged: ((Bool) -> Void)?
    var onOcclusionChanged: ((Bool) -> Void)?
    var onLODChanged: ((Bool) -> Void)?
    var onHUDChanged: ((Bool) -> Void)?
    var onMinimapChanged: ((Bool) -> Void)?
    var onCrosshairChanged: ((Bool) -> Void)?

    private let materialPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lodTintPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let blockMaterialPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let frustumToggle = NSButton(
        checkboxWithTitle: "Frustum culling", target: nil, action: nil)
    private let occlusionToggle = NSButton(
        checkboxWithTitle: "Occlusion culling", target: nil, action: nil)
    private let lodToggle = NSButton(checkboxWithTitle: "LOD enabled", target: nil, action: nil)
    private let hudToggle = NSButton(checkboxWithTitle: "HUD", target: nil, action: nil)
    private let minimapToggle = NSButton(checkboxWithTitle: "Minimap", target: nil, action: nil)
    private let crosshairToggle = NSButton(checkboxWithTitle: "Crosshair", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        let title = NSTextField(labelWithString: "Debug Panel (Tab to close)")
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = .white

        let materialLabel = NSTextField(labelWithString: "Material mode")
        materialLabel.textColor = .white
        materialPopup.addItems(withTitles: MaterialDebugMode.allCases.map(\.displayName))
        materialPopup.target = self
        materialPopup.action = #selector(materialPopupChanged)

        let lodTintLabel = NSTextField(labelWithString: "LOD tint overlay")
        lodTintLabel.textColor = .white
        lodTintPopup.addItems(withTitles: [LODTintOverlayMode.off, .subtle].map(\.displayName))
        lodTintPopup.target = self
        lodTintPopup.action = #selector(lodTintPopupChanged)

        let blockMaterialLabel = NSTextField(labelWithString: "Placed block type")
        blockMaterialLabel.textColor = .white
        blockMaterialPopup.addItems(withTitles: BlockMaterialType.allCases.map(\.displayName))
        blockMaterialPopup.target = self
        blockMaterialPopup.action = #selector(blockMaterialPopupChanged)

        [frustumToggle, occlusionToggle, lodToggle, hudToggle, minimapToggle, crosshairToggle]
            .forEach {
                $0.target = self
                $0.action = #selector(toggleChanged(_:))
            }

        let stack = NSStackView(views: [
            title,
            materialLabel,
            materialPopup,
            lodTintLabel,
            lodTintPopup,
            blockMaterialLabel,
            blockMaterialPopup,
            frustumToggle,
            occlusionToggle,
            lodToggle,
            hudToggle,
            minimapToggle,
            crosshairToggle,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 270),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        materialMode: MaterialDebugMode,
        lodTintOverlayMode: LODTintOverlayMode,
        blockMaterial: BlockMaterialType,
        frustumEnabled: Bool,
        occlusionEnabled: Bool,
        lodEnabled: Bool,
        hudVisible: Bool,
        minimapVisible: Bool,
        crosshairVisible: Bool
    ) {
        materialPopup.selectItem(at: MaterialDebugMode.allCases.firstIndex(of: materialMode) ?? 0)
        lodTintPopup.selectItem(
            at: [LODTintOverlayMode.off, .subtle].firstIndex(of: lodTintOverlayMode) ?? 0)
        blockMaterialPopup.selectItem(
            at: BlockMaterialType.allCases.firstIndex(of: blockMaterial) ?? 0)
        frustumToggle.state = frustumEnabled ? .on : .off
        occlusionToggle.state = occlusionEnabled ? .on : .off
        lodToggle.state = lodEnabled ? .on : .off
        hudToggle.state = hudVisible ? .on : .off
        minimapToggle.state = minimapVisible ? .on : .off
        crosshairToggle.state = crosshairVisible ? .on : .off
    }

    @objc private func materialPopupChanged() {
        let index = materialPopup.indexOfSelectedItem
        guard MaterialDebugMode.allCases.indices.contains(index) else { return }
        onMaterialModeChanged?(MaterialDebugMode.allCases[index])
    }

    @objc private func lodTintPopupChanged() {
        let modes: [LODTintOverlayMode] = [.off, .subtle]
        let index = lodTintPopup.indexOfSelectedItem
        guard modes.indices.contains(index) else { return }
        onLODOverlayModeChanged?(modes[index])
    }

    @objc private func blockMaterialPopupChanged() {
        let index = blockMaterialPopup.indexOfSelectedItem
        guard BlockMaterialType.allCases.indices.contains(index) else { return }
        onBlockMaterialChanged?(BlockMaterialType.allCases[index])
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        let value = sender.state == .on
        switch sender {
        case frustumToggle:
            onFrustumChanged?(value)
        case occlusionToggle:
            onOcclusionChanged?(value)
        case lodToggle:
            onLODChanged?(value)
        case hudToggle:
            onHUDChanged?(value)
        case minimapToggle:
            onMinimapChanged?(value)
        case crosshairToggle:
            onCrosshairChanged?(value)
        default:
            break
        }
    }
}
