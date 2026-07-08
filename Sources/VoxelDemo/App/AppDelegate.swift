import Cocoa
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowTitle = "VoxelDemo — powered by VoxelEngine"

    private var window: NSWindow?
    private var gameView: MetalView?
    private var eventMonitor: Any?
    private var recentWorldsMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        window.title = windowTitle
        window.center()
        window.minSize = NSSize(width: 960, height: 640)
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
}

// MARK: - Menu state

extension AppDelegate: NSMenuDelegate {
    /// Rebuilds File ▸ Open Recent each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
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
        case #selector(clearRecentWorlds(_:)):
            return !RecentWorldsStore().paths().isEmpty
        default:
            break
        }
        return true
    }
}
