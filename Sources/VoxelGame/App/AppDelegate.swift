import Cocoa
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var gameView: MetalView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        window.title = "Physics Voxel Engine"
        window.center()
        window.acceptsMouseMovedEvents = true

        do {
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

        CGDisplayHideCursor(CGMainDisplayID())
        CGAssociateMouseAndMouseCursorPosition(0)

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .mouseMoved]) {
            [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 {
                NSApp.terminate(nil)
            }

            self?.gameView?.handleEvent(event)
            return event
        }
    }
}
