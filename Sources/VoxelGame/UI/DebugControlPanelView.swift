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
 var onLookSensitivityChanged: ((Float) -> Void)?
 var onFieldOfViewChanged: ((Float) -> Void)?

 private let materialPopup = NSPopUpButton(frame: .zero, pullsDown: false)
 private let lodTintPopup = NSPopUpButton(frame: .zero, pullsDown: false)
 private let blockMaterialPopup = NSPopUpButton(frame: .zero, pullsDown: false)
 private let frustumToggle = NSButton(
  checkboxWithTitle: "Frustum culling", target: nil, action: nil)
 private let occlusionToggle = NSButton(
  checkboxWithTitle: "Occlusion culling", target: nil, action: nil)
 private let lodToggle = NSButton(checkboxWithTitle: "LOD meshing", target: nil, action: nil)
 private let hudToggle = NSButton(checkboxWithTitle: "Compact HUD", target: nil, action: nil)
 private let minimapToggle = NSButton(checkboxWithTitle: "Minimap", target: nil, action: nil)
 private let crosshairToggle = NSButton(checkboxWithTitle: "Crosshair", target: nil, action: nil)

 private let sensitivitySlider = NSSlider(
  value: 0.005, minValue: 0.001, maxValue: 0.012,
  target: nil, action: nil)
 private let fovSlider = NSSlider(
  value: 65, minValue: 50, maxValue: 100,
  target: nil, action: nil)
 private let sensitivityLabel = NSTextField(labelWithString: "")
 private let fovLabel = NSTextField(labelWithString: "")

 private let cameraSummaryLabel = DebugPanelSummaryLabel()
 private let worldSummaryLabel = DebugPanelSummaryLabel()
 private let performanceSummaryLabel = DebugPanelSummaryLabel()

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

  let title = makeSectionTitle("Debug Inspector")
  let subtitle = NSTextField(
   labelWithString: "Tab or ⌥⌘I closes this panel. Mouse look pauses while it is open.")
  subtitle.font = .systemFont(ofSize: 11)
  subtitle.textColor = NSColor.white.withAlphaComponent(0.72)

  let controlsStack = NSStackView(views: [
   makeLabeledControlRow(title: "Material mode", control: materialPopup),
   makeLabeledControlRow(title: "LOD tint", control: lodTintPopup),
   makeLabeledControlRow(title: "Placed block", control: blockMaterialPopup),
   makeLabeledControlRow(title: "Sensitivity", control: sensitivityLabelRow()),
   makeLabeledControlRow(title: "Field of view", control: fovLabelRow()),
  ])
  controlsStack.orientation = .vertical
  controlsStack.spacing = 8

  materialPopup.addItems(withTitles: MaterialDebugMode.allCases.map(\.displayName))
  materialPopup.target = self
  materialPopup.action = #selector(materialPopupChanged)

  lodTintPopup.addItems(withTitles: LODTintOverlayMode.allCases.map(\.displayName))
  lodTintPopup.target = self
  lodTintPopup.action = #selector(lodTintPopupChanged)

  blockMaterialPopup.addItems(withTitles: BlockMaterialType.allCases.map(\.displayName))
  blockMaterialPopup.target = self
  blockMaterialPopup.action = #selector(blockMaterialPopupChanged)

  [frustumToggle, occlusionToggle, lodToggle, hudToggle, minimapToggle, crosshairToggle]
   .forEach {
    $0.target = self
    $0.action = #selector(toggleChanged(_:))
   }

  sensitivitySlider.target = self
  sensitivitySlider.action = #selector(sensitivitySliderChanged)
  fovSlider.target = self
  fovSlider.action = #selector(fovSliderChanged)
  [sensitivityLabel, fovLabel].forEach {
   $0.font = .systemFont(ofSize: 11)
   $0.textColor = NSColor.white.withAlphaComponent(0.6)
   $0.alignment = .right
  }

  let togglesGrid = NSGridView(views: [
   [frustumToggle, occlusionToggle],
   [lodToggle, hudToggle],
   [minimapToggle, crosshairToggle],
  ])
  togglesGrid.translatesAutoresizingMaskIntoConstraints = false
  togglesGrid.rowSpacing = 6
  togglesGrid.columnSpacing = 14
  togglesGrid.xPlacement = .leading

  let stack = NSStackView(views: [
   title,
   subtitle,
   makeDivider(),
   makeSectionTitle("Quick controls"),
   controlsStack,
   makeDivider(),
   makeSectionTitle("Visibility"),
   togglesGrid,
   makeDivider(),
   makeSectionTitle("Camera"),
   cameraSummaryLabel,
   makeSectionTitle("World"),
   worldSummaryLabel,
   makeSectionTitle("Performance"),
   performanceSummaryLabel,
  ])
  stack.orientation = .vertical
  stack.alignment = .leading
  stack.spacing = 10
  stack.translatesAutoresizingMaskIntoConstraints = false
  addSubview(stack)

  NSLayoutConstraint.activate([
   widthAnchor.constraint(equalToConstant: 320),
   stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
   stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
   stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
   stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
  ])
 }

 required init?(coder: NSCoder) {
  fatalError("init(coder:) has not been implemented")
 }

 func update(
  materialMode: MaterialDebugMode,
  lodTintOverlayMode: LODTintOverlayMode,
  blockMaterial: BlockMaterialType,
  lookSensitivity: Float,
  fieldOfViewDegrees: Float,
  frustumEnabled: Bool,
  occlusionEnabled: Bool,
  lodEnabled: Bool,
  hudVisible: Bool,
  minimapVisible: Bool,
  crosshairVisible: Bool,
  snapshot: DebugHUDSnapshot
 ) {
  materialPopup.selectItem(at: MaterialDebugMode.allCases.firstIndex(of: materialMode) ?? 0)
  lodTintPopup.selectItem(
   at: LODTintOverlayMode.allCases.firstIndex(of: lodTintOverlayMode) ?? 0)
  blockMaterialPopup.selectItem(
   at: BlockMaterialType.allCases.firstIndex(of: blockMaterial) ?? 0)
  frustumToggle.state = frustumEnabled ? .on : .off
  occlusionToggle.state = occlusionEnabled ? .on : .off
  lodToggle.state = lodEnabled ? .on : .off
  hudToggle.state = hudVisible ? .on : .off
  minimapToggle.state = minimapVisible ? .on : .off
  crosshairToggle.state = crosshairVisible ? .on : .off

  sensitivitySlider.floatValue = lookSensitivity
  sensitivityLabel.stringValue = String(format: "%.3f", lookSensitivity)
  fovSlider.floatValue = fieldOfViewDegrees
  fovLabel.stringValue = "\(Int(fieldOfViewDegrees))°"
  cameraSummaryLabel.stringValue =
   "Position  x=\(format(snapshot.cameraPosition.x))  y=\(format(snapshot.cameraPosition.y))  z=\(format(snapshot.cameraPosition.z))\nYaw  \(format(snapshot.yawDegrees))°    Pitch  \(format(snapshot.pitchDegrees))°\nTarget  \(snapshot.targetCellDescription)"
  worldSummaryLabel.stringValue =
   "Seed  \(snapshot.worldSeed.map(String.init) ?? "n/a")    Place  \(snapshot.selectedPlacementMaterial)\nVisible chunks  \(snapshot.visibleChunkCount)    Vertices  \(snapshot.vertexCount)\nLOD rings  \(snapshot.lodDistribution.isEmpty ? "none" : snapshot.lodDistribution)"
  performanceSummaryLabel.stringValue =
   "Frame time  \(format(snapshot.frameTimeMilliseconds)) ms\nFPS  \(format(snapshot.framesPerSecond))\nMaterial  \(snapshot.materialDebugMode)    Tint  \(snapshot.lodTintOverlayMode)"
 }

 @objc private func materialPopupChanged() {
  let index = materialPopup.indexOfSelectedItem
  guard MaterialDebugMode.allCases.indices.contains(index) else { return }
  onMaterialModeChanged?(MaterialDebugMode.allCases[index])
 }

 @objc private func lodTintPopupChanged() {
  let index = lodTintPopup.indexOfSelectedItem
  guard LODTintOverlayMode.allCases.indices.contains(index) else { return }
  onLODOverlayModeChanged?(LODTintOverlayMode.allCases[index])
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

 private func makeSectionTitle(_ title: String) -> NSTextField {
  let label = NSTextField(labelWithString: title)
  label.font = .systemFont(ofSize: 12, weight: .semibold)
  label.textColor = .white
  return label
 }

 private func makeDivider() -> NSBox {
  let divider = NSBox()
  divider.boxType = .separator
  divider.translatesAutoresizingMaskIntoConstraints = false
  return divider
 }

 private func makeLabeledControlRow(title: String, control: NSView) -> NSStackView {
  let label = NSTextField(labelWithString: title)
  label.textColor = NSColor.white.withAlphaComponent(0.86)
  label.font = .systemFont(ofSize: 11, weight: .medium)

  let row = NSStackView(views: [label, control])
  row.orientation = .vertical
  row.alignment = .leading
  row.spacing = 4
  return row
 }

 @objc private func sensitivitySliderChanged() {
  let value = sensitivitySlider.floatValue
  sensitivityLabel.stringValue = String(format: "%.3f", value)
  onLookSensitivityChanged?(value)
 }

 @objc private func fovSliderChanged() {
  let value = fovSlider.floatValue
  fovLabel.stringValue = "\(Int(value))°"
  onFieldOfViewChanged?(value)
 }

 private func sensitivityLabelRow() -> NSStackView {
  let row = NSStackView(views: [sensitivitySlider, sensitivityLabel])
  row.spacing = 8
  sensitivitySlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
  return row
 }

 private func fovLabelRow() -> NSStackView {
  let row = NSStackView(views: [fovSlider, fovLabel])
  row.spacing = 8
  fovSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
  return row
 }

 private func format(_ value: Float) -> String {
  String(format: "%.2f", value)
 }
}

@MainActor
private final class DebugPanelSummaryLabel: NSTextField {
 init() {
  super.init(frame: .zero)
  isEditable = false
  isBordered = false
  drawsBackground = false
  isSelectable = false
  font = .monospacedSystemFont(ofSize: 11, weight: .regular)
  textColor = NSColor.white.withAlphaComponent(0.9)
  maximumNumberOfLines = 0
  lineBreakMode = .byWordWrapping
  setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
 }

 required init?(coder: NSCoder) {
  fatalError("init(coder:) has not been implemented")
 }
}
