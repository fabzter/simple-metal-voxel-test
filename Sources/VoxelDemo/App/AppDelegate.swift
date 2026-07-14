import Cocoa
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowTitle = "VoxelDemo — powered by VoxelEngine"

    private var window: NSWindow?
    private var gameView: MetalView?
    private var eventMonitor: Any?
    private var recentWorldsMenu: NSMenu?
    private weak var trackedViewMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        window.title = windowTitle
        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setFrameAutosaveName("VoxelDemoMainWindow")
        window.minSize = NSSize(width: 960, height: 640)
        if let aspectSize = SettingsStore().aspectRatio.size {
            window.contentAspectRatio = aspectSize
        }
        window.acceptsMouseMovedEvents = true
        configureMenus()

        do {
            // Startup can fail if Metal is unavailable or one of the renderer resources cannot be
            // created. Surface that cleanly instead of crashing.
            let gameView = try MetalView.make(frame: frame)
            window.contentView = gameView
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(gameView)

            self.window = window
            self.gameView = gameView
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown, .keyUp, .mouseMoved, .leftMouseDown, .rightMouseDown, .flagsChanged,
            ]) {
                [weak self] event in
                self?.gameView?.handleEvent(event)
                return event
            }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        gameView?.saveWorldToDisk()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func configureMenus() {
        let appName = ProcessInfo.processInfo.processName

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: appName)
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        let settingsItem = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        let newWorldItem = fileMenu.addItem(
            withTitle: "New World", action: #selector(newWorld(_:)), keyEquivalent: "n")
        newWorldItem.keyEquivalentModifierMask = [.command]
        let newSeedItem = fileMenu.addItem(
            withTitle: "New World from Seed…",
            action: #selector(newWorldFromSeed(_:)),
            keyEquivalent: "n")
        newSeedItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        let openItem = fileMenu.addItem(
            withTitle: "Open World…", action: #selector(openWorld(_:)), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        fileMenu.addItem(openRecentItem)
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self  // Rebuilt on demand in menuNeedsUpdate.
        openRecentItem.submenu = recentMenu
        self.recentWorldsMenu = recentMenu
        fileMenu.addItem(
            withTitle: "Revert to Saved", action: #selector(revertToSaved(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        let saveItem = fileMenu.addItem(
            withTitle: "Save World", action: #selector(saveWorld(_:)), keyEquivalent: "s")
        saveItem.keyEquivalentModifierMask = [.command]
        let saveAsItem = fileMenu.addItem(
            withTitle: "Save World As…", action: #selector(saveWorldAs(_:)), keyEquivalent: "s")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Reset World…", action: #selector(resetWorld(_:)), keyEquivalent: "")
        fileMenuItem.submenu = fileMenu

        // A standard Edit menu so text fields (e.g. the seed dialog) support
        // ⌘C/⌘V/⌘X/⌘A — without it, paste doesn't work in modal alerts.
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(
            withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let gameMenuItem = NSMenuItem(title: "Game", action: nil, keyEquivalent: "")
        mainMenu.addItem(gameMenuItem)

        let gameMenu = NSMenu(title: "Game")
        // ⌥⌘F mirrors the in-game F key the way ⌥⌘H mirrors F1. A bare "f" key
        // equivalent would race the game's local event monitor and double-toggle.
        let flyItem = gameMenu.addItem(
            withTitle: "Toggle Fly Mode", action: #selector(toggleFlyMode(_:)), keyEquivalent: "f")
        flyItem.keyEquivalentModifierMask = [.option, .command]
        gameMenu.addItem(.separator())
        let copySeedItem = gameMenu.addItem(
            withTitle: "Copy World Seed", action: #selector(copyWorldSeed(_:)), keyEquivalent: "c")
        copySeedItem.keyEquivalentModifierMask = [.command, .shift]
        gameMenu.addItem(.separator())
        gameMenu.addItem(
            withTitle: "Sound Effects", action: #selector(toggleSoundEffects(_:)), keyEquivalent: ""
        )
        gameMenuItem.submenu = gameMenu

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)

        let viewMenu = NSMenu(title: "View")
        viewMenu.delegate = self
        trackedViewMenu = viewMenu
        let windowSizeItem = NSMenuItem(title: "Window Size", action: nil, keyEquivalent: "")
        let windowSizeMenu = NSMenu(title: "Window Size")
        for (width, height) in [(1024, 768), (1280, 720), (1600, 900), (1920, 1080)] {
            let item = NSMenuItem(
                title: "\(width)×\(height)",
                action: #selector(setWindowSize(_:)),
                keyEquivalent: "")
            // Pack width + height into one Int so the selector can stay a tiny Objective-C bridge.
            item.tag = width * 10_000 + height
            windowSizeMenu.addItem(item)
        }
        windowSizeItem.submenu = windowSizeMenu
        viewMenu.addItem(windowSizeItem)

        let aspectRatioItem = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        let aspectRatioMenu = NSMenu(title: "Aspect Ratio")
        for aspectRatio in WindowAspectRatio.allCases {
            let item = NSMenuItem(
                title: aspectRatio.displayName,
                action: #selector(setAspectRatio(_:)),
                keyEquivalent: "")
            item.representedObject = aspectRatio.rawValue
            aspectRatioMenu.addItem(item)
        }
        aspectRatioItem.submenu = aspectRatioMenu
        viewMenu.addItem(aspectRatioItem)

        let renderScaleItem = NSMenuItem(
            title: "Render Resolution", action: nil, keyEquivalent: "")
        let renderScaleMenu = NSMenu(title: "Render Resolution")
        for percent in [50, 75, 100, 125, 150, 200] {
            let item = NSMenuItem(
                title: "\(percent)%",
                action: #selector(setRenderScale(_:)),
                keyEquivalent: "")
            item.tag = percent
            renderScaleMenu.addItem(item)
        }
        renderScaleItem.submenu = renderScaleMenu
        viewMenu.addItem(renderScaleItem)
        viewMenu.addItem(.separator())
        let fullscreenItem = viewMenu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullscreenItem.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(.separator())
        let inspectorItem = viewMenu.addItem(
            withTitle: "Toggle Debug Inspector",
            action: #selector(toggleDebugInspector(_:)),
            keyEquivalent: "i")
        inspectorItem.keyEquivalentModifierMask = [.option, .command]

        let hudItem = viewMenu.addItem(
            withTitle: "Toggle Compact HUD",
            action: #selector(toggleCompactHUD(_:)),
            keyEquivalent: "h")
        hudItem.keyEquivalentModifierMask = [.option, .command]

        let minimapItem = viewMenu.addItem(
            withTitle: "Toggle Minimap",
            action: #selector(toggleMinimap(_:)),
            keyEquivalent: "m")
        minimapItem.keyEquivalentModifierMask = [.option, .command]

        let crosshairItem = viewMenu.addItem(
            withTitle: "Toggle Crosshair",
            action: #selector(toggleCrosshair(_:)),
            keyEquivalent: "c")
        crosshairItem.keyEquivalentModifierMask = [.option, .command]
        viewMenuItem.submenu = viewMenu

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        let minimizeItem = windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        minimizeItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        mainMenu.addItem(helpMenuItem)

        let helpMenu = NSMenu(title: "Help")
        let controlsItem = helpMenu.addItem(
            withTitle: "Toggle Controls Overlay",
            action: #selector(toggleControlsOverlay(_:)),
            keyEquivalent: "/")
        controlsItem.keyEquivalentModifierMask = [.command, .shift]
        helpMenuItem.submenu = helpMenu

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }

    @objc private func toggleDebugInspector(_ sender: Any?) {
        gameView?.toggleDebugInspector()
    }

    @objc private func toggleCompactHUD(_ sender: Any?) {
        gameView?.toggleHUDVisibility()
    }

    @objc private func toggleMinimap(_ sender: Any?) {
        gameView?.toggleMinimapVisibility()
    }

    @objc private func toggleCrosshair(_ sender: Any?) {
        gameView?.toggleCrosshairVisibility()
    }

    @objc private func toggleControlsOverlay(_ sender: Any?) {
        gameView?.toggleHelpOverlay()
    }

    @objc private func saveWorld(_ sender: Any?) {
        gameView?.saveWorldToDisk()
    }

    @objc private func saveWorldAs(_ sender: Any?) {
        gameView?.saveWorldAs()
    }

    @objc private func newWorld(_ sender: Any?) {
        gameView?.newRandomWorld()
    }

    @objc private func newWorldFromSeed(_ sender: Any?) {
        gameView?.promptForSeedAndCreateWorld()
    }

    @objc private func openWorld(_ sender: Any?) {
        gameView?.openWorld()
    }

    @objc private func revertToSaved(_ sender: Any?) {
        gameView?.revertToSaved()
    }

    @objc private func toggleFlyMode(_ sender: Any?) {
        gameView?.toggleFlyModeFromMenu()
    }

    @objc private func copyWorldSeed(_ sender: Any?) {
        gameView?.copyWorldSeed()
    }

    @objc private func toggleSoundEffects(_ sender: Any?) {
        gameView?.toggleSoundEffects()
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsWindowController.show()
    }

    @objc private func openRecentWorld(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        gameView?.openRecentWorld(atPath: path)
    }

    @objc private func clearRecentWorlds(_ sender: Any?) {
        gameView?.clearRecentWorlds()
    }

    @objc private func resetWorld(_ sender: Any?) {
        gameView?.resetWorld()
    }

    @objc private func setWindowSize(_ sender: NSMenuItem) {
        let width = sender.tag / 10_000
        let height = sender.tag % 10_000
        window?.setContentSize(NSSize(width: width, height: height))
    }

    @objc private func setAspectRatio(_ sender: NSMenuItem) {
        let aspectRatio =
            WindowAspectRatio(rawValue: sender.representedObject as? String ?? "")
            ?? .free
        applyAspectRatio(aspectRatio)
    }

    @objc private func setRenderScale(_ sender: NSMenuItem) {
        gameView?.setRenderScale(CGFloat(sender.tag) / 100)
    }

    private func applyAspectRatio(_ aspectRatio: WindowAspectRatio) {
        var settings = SettingsStore()
        settings.aspectRatio = aspectRatio

        guard let window else { return }
        guard let size = aspectRatio.size else {
            window.contentAspectRatio = .zero
            return
        }

        window.contentAspectRatio = size
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        let minimumWidthForAspect = ceil(window.minSize.height * size.width / size.height)
        let snappedWidth = max(contentSize.width, window.minSize.width, minimumWidthForAspect)
        let snappedHeight = round(snappedWidth * size.height / size.width)
        window.setContentSize(NSSize(width: snappedWidth, height: snappedHeight))
    }

    private lazy var settingsWindowController: SettingsWindowController = {
        let controller = SettingsWindowController()
        controller.onRenderScaleChanged = { [weak self] scale in
            self?.gameView?.setRenderScale(scale)
        }
        controller.onAspectRatioChanged = { [weak self] aspectRatio in
            self?.applyAspectRatio(aspectRatio)
        }
        controller.onLookSensitivityChanged = { [weak self] value in
            self?.gameView?.setLookSensitivity(value)
        }
        controller.onInvertLookYChanged = { [weak self] value in
            self?.gameView?.setInvertLookY(value)
        }
        controller.onFieldOfViewChanged = { [weak self] value in
            self?.gameView?.setFieldOfView(value)
        }
        controller.onSoundEnabledChanged = { [weak self] value in
            self?.gameView?.setSoundEnabled(value)
        }
        controller.onMasterVolumeChanged = { [weak self] value in
            self?.gameView?.setMasterVolume(value)
        }
        return controller
    }()
}

// MARK: - Menu state

extension AppDelegate: NSMenuDelegate {
    /// Rebuilds File ▸ Open Recent each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === trackedViewMenu {
            menu.items.first { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }?.title =
                (window?.styleMask.contains(.fullScreen) ?? false)
                ? "Exit Full Screen" : "Enter Full Screen"
            return
        }

        guard menu === recentWorldsMenu else { return }
        menu.removeAllItems()

        let paths = RecentWorldsStore().paths()
        for path in paths {
            let item = NSMenuItem(
                title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                action: #selector(openRecentWorld(_:)),
                keyEquivalent: "")
            item.representedObject = path
            menu.addItem(item)
        }
        if paths.isEmpty {
            let empty = NSMenuItem(title: "No Recent Worlds", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(
            title: "Clear Menu", action: #selector(clearRecentWorlds(_:)), keyEquivalent: "")
        menu.addItem(clear)
    }
}

extension AppDelegate: NSMenuItemValidation {
    /// Reflects live game state as menu checkmarks (fly mode, sound).
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFlyMode(_:)):
            menuItem.state = (gameView?.isPlayerFlying ?? false) ? .on : .off
        case #selector(toggleSoundEffects(_:)):
            menuItem.state = (gameView?.isSoundEnabled ?? true) ? .on : .off
        case #selector(setAspectRatio(_:)):
            let rawValue = menuItem.representedObject as? String
            menuItem.state = rawValue == SettingsStore().aspectRatio.rawValue ? .on : .off
            return !(window?.styleMask.contains(.fullScreen) ?? false)
        case #selector(setRenderScale(_:)):
            menuItem.state =
                abs((gameView?.currentRenderScale ?? 1) * 100 - CGFloat(menuItem.tag)) < 1
                ? .on : .off
        case #selector(setWindowSize(_:)):
            return !(window?.styleMask.contains(.fullScreen) ?? false)
        case #selector(clearRecentWorlds(_:)):
            return !RecentWorldsStore().paths().isEmpty
        default:
            break
        }
        return true
    }
}
