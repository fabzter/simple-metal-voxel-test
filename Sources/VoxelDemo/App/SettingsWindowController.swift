import Cocoa

@MainActor
final class SettingsWindowController: NSWindowController {
    var onRenderScaleChanged: ((CGFloat) -> Void)?
    var onAspectRatioChanged: ((WindowAspectRatio) -> Void)?
    var onLookSensitivityChanged: ((Float) -> Void)?
    var onInvertLookYChanged: ((Bool) -> Void)?
    var onFieldOfViewChanged: ((Float) -> Void)?
    var onSoundEnabledChanged: ((Bool) -> Void)?
    var onMasterVolumeChanged: ((Float) -> Void)?

    private let renderScalePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let aspectRatioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sensitivitySlider = NSSlider(
        value: 0.005, minValue: 0.001, maxValue: 0.012, target: nil, action: nil)
    private let sensitivityValueLabel = NSTextField(labelWithString: "")
    private let invertLookYToggle = NSButton(
        checkboxWithTitle: "Enable", target: nil, action: nil)
    private let fieldOfViewSlider = NSSlider(
        value: 65, minValue: 50, maxValue: 100, target: nil, action: nil)
    private let fieldOfViewValueLabel = NSTextField(labelWithString: "")
    private let soundEffectsToggle = NSButton(
        checkboxWithTitle: "Enable", target: nil, action: nil)
    private let masterVolumeSlider = NSSlider(
        value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let masterVolumeValueLabel = NSTextField(labelWithString: "")

    init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        super.init(window: nil)

        configurePopups()
        configureActions()
        configureValueLabels()

        tabs.addTabViewItem(makeDisplayPane())
        tabs.addTabViewItem(makeControlsPane())
        tabs.addTabViewItem(makeSoundPane())

        let window = NSWindow(contentViewController: tabs)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 260))
        window.isReleasedWhenClosed = false
        self.window = window
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Refresh from the store each time the window opens. The debug inspector re-reads
    /// live values every frame; Settings stays native and only resyncs when shown.
    func show() {
        let settings = SettingsStore()
        renderScalePopup.selectItem(withTag: Int(round(settings.renderScale * 100)))
        let aspectIndex = WindowAspectRatio.allCases.firstIndex(of: settings.aspectRatio) ?? 0
        aspectRatioPopup.selectItem(at: aspectIndex)

        sensitivitySlider.floatValue = settings.lookSensitivity
        sensitivityValueLabel.stringValue = Self.sensitivityString(settings.lookSensitivity)

        invertLookYToggle.state = settings.invertLookY ? .on : .off

        fieldOfViewSlider.floatValue = settings.fieldOfViewDegrees
        fieldOfViewValueLabel.stringValue = Self.fieldOfViewString(settings.fieldOfViewDegrees)

        soundEffectsToggle.state = settings.soundEnabled ? .on : .off

        masterVolumeSlider.floatValue = settings.masterVolume
        masterVolumeValueLabel.stringValue = Self.volumeString(settings.masterVolume)

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configurePopups() {
        for percent in [50, 75, 100, 125, 150, 200] {
            renderScalePopup.addItem(withTitle: "\(percent)%")
            renderScalePopup.lastItem?.tag = percent
        }

        for ratio in WindowAspectRatio.allCases {
            aspectRatioPopup.addItem(withTitle: ratio.displayName)
            aspectRatioPopup.lastItem?.representedObject = ratio.rawValue
        }
    }

    private func configureActions() {
        renderScalePopup.target = self
        renderScalePopup.action = #selector(renderScaleChanged)

        aspectRatioPopup.target = self
        aspectRatioPopup.action = #selector(aspectRatioChanged)

        sensitivitySlider.target = self
        sensitivitySlider.action = #selector(sensitivityChanged)

        invertLookYToggle.target = self
        invertLookYToggle.action = #selector(invertLookYChanged)

        fieldOfViewSlider.target = self
        fieldOfViewSlider.action = #selector(fieldOfViewChanged)

        soundEffectsToggle.target = self
        soundEffectsToggle.action = #selector(soundEffectsChanged)

        masterVolumeSlider.target = self
        masterVolumeSlider.action = #selector(masterVolumeChanged)
    }

    private func configureValueLabels() {
        [sensitivityValueLabel, fieldOfViewValueLabel, masterVolumeValueLabel].forEach {
            $0.alignment = .right
            $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            $0.textColor = .secondaryLabelColor
        }
    }

    private func makeDisplayPane() -> NSTabViewItem {
        let caption = NSTextField(
            labelWithString: "Window sizes live in View ▸ Window Size.")
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 0
        caption.lineBreakMode = .byWordWrapping

        let grid = makeGrid(rows: [
            ("Render Resolution", renderScalePopup),
            ("Aspect Ratio", aspectRatioPopup),
        ])

        let viewController = makePaneController(content: [grid, caption])
        let item = NSTabViewItem(viewController: viewController)
        item.label = "Display"
        item.image = NSImage(
            systemSymbolName: "display", accessibilityDescription: "Display")
        return item
    }

    private func makeControlsPane() -> NSTabViewItem {
        let sensitivityRow = valueRow(
            slider: sensitivitySlider,
            valueLabel: sensitivityValueLabel)
        let fieldOfViewRow = valueRow(
            slider: fieldOfViewSlider,
            valueLabel: fieldOfViewValueLabel)

        let grid = makeGrid(rows: [
            ("Mouse Sensitivity", sensitivityRow),
            ("Invert Look Y", invertLookYToggle),
            ("Field of View", fieldOfViewRow),
        ])

        let viewController = makePaneController(content: [grid])
        let item = NSTabViewItem(viewController: viewController)
        item.label = "Controls"
        item.image = NSImage(
            systemSymbolName: "keyboard", accessibilityDescription: "Controls")
        return item
    }

    private func makeSoundPane() -> NSTabViewItem {
        let masterVolumeRow = valueRow(
            slider: masterVolumeSlider,
            valueLabel: masterVolumeValueLabel)
        let grid = makeGrid(rows: [
            ("Sound Effects", soundEffectsToggle),
            ("Master Volume", masterVolumeRow),
        ])

        let viewController = makePaneController(content: [grid])
        let item = NSTabViewItem(viewController: viewController)
        item.label = "Sound"
        item.image = NSImage(
            systemSymbolName: "speaker.wave.2", accessibilityDescription: "Sound")
        return item
    }

    private func makePaneController(content: [NSView]) -> NSViewController {
        let stack = NSStackView(views: content)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])

        let viewController = NSViewController()
        viewController.view = container
        return viewController
    }

    private func makeGrid(rows: [(String, NSView)]) -> NSGridView {
        let gridRows = rows.map { (title, control) in
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .labelColor
            return [label, control]
        }

        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.xPlacement = .leading
        grid.yPlacement = .center
        return grid
    }

    private func valueRow(slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let row = NSStackView(views: [slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        return row
    }

    @objc private func renderScaleChanged() {
        let selectedTag = renderScalePopup.selectedTag()
        guard selectedTag > 0 else { return }
        onRenderScaleChanged?(CGFloat(selectedTag) / 100)
    }

    @objc private func aspectRatioChanged() {
        guard
            let rawValue = aspectRatioPopup.selectedItem?.representedObject as? String,
            let aspectRatio = WindowAspectRatio(rawValue: rawValue)
        else { return }
        onAspectRatioChanged?(aspectRatio)
    }

    @objc private func sensitivityChanged() {
        let value = sensitivitySlider.floatValue
        sensitivityValueLabel.stringValue = Self.sensitivityString(value)
        onLookSensitivityChanged?(value)
    }

    @objc private func invertLookYChanged() {
        onInvertLookYChanged?(invertLookYToggle.state == .on)
    }

    @objc private func fieldOfViewChanged() {
        let value = fieldOfViewSlider.floatValue
        fieldOfViewValueLabel.stringValue = Self.fieldOfViewString(value)
        onFieldOfViewChanged?(value)
    }

    @objc private func soundEffectsChanged() {
        onSoundEnabledChanged?(soundEffectsToggle.state == .on)
    }

    @objc private func masterVolumeChanged() {
        let value = masterVolumeSlider.floatValue
        masterVolumeValueLabel.stringValue = Self.volumeString(value)
        onMasterVolumeChanged?(value)
    }

    private static func sensitivityString(_ value: Float) -> String {
        String(format: "%.3f", value)
    }

    private static func fieldOfViewString(_ value: Float) -> String {
        "\(Int(value))°"
    }

    private static func volumeString(_ value: Float) -> String {
        "\(Int(round(value * 100)))%"
    }
}
