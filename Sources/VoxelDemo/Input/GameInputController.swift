import Cocoa
import VoxelEngine
import simd

@MainActor
final class GameInputController {
    private enum KeyCode {
        static let a: UInt16 = 0
        static let s: UInt16 = 1
        static let d: UInt16 = 2
        static let w: UInt16 = 13
        static let space: UInt16 = 49
        static let tab: UInt16 = 48
        static let f: UInt16 = 3
    }

    private var playerInput = PlayerInput()
    private var pendingLookDelta = SIMD2<Float>(repeating: 0)
    private var pendingEditActions: [BlockEditAction] = []
    private var pendingMaterialDebugToggle = false
    private var pendingPanelToggle = false
    private var pendingHUDToggle = false
    private var pendingBlockMaterialSelection: BlockMaterialType?
    private var pendingEscape = false
    private var pendingFlyToggle = false
    private var pendingScrollSteps = 0

    var currentInput: PlayerInput {
        playerInput
    }

    func handle(_ event: NSEvent, gameplayInputEnabled: Bool) {
        switch event.type {
        case .keyDown:
            if event.keyCode == KeyCode.tab {
                pendingPanelToggle = true
            }
            if event.keyCode == 53 {  // Esc — always available, even with inspector open
                pendingEscape = true
            }
            if event.keyCode == KeyCode.f {
                pendingFlyToggle = true
            }
            if event.specialKey == .f1 {
                pendingHUDToggle = true
            }
            if gameplayInputEnabled {
                if event.charactersIgnoringModifiers?.lowercased() == "m" {
                    pendingMaterialDebugToggle = true
                }
                if let material = blockMaterialShortcut(in: event) {
                    pendingBlockMaterialSelection = material
                }
                setKeyState(for: event.keyCode, isPressed: true)
            }
        case .keyUp:
            setKeyState(for: event.keyCode, isPressed: false)
        case .mouseMoved:
            if gameplayInputEnabled {
                pendingLookDelta += SIMD2(Float(event.deltaX), Float(event.deltaY))
            }
        case .leftMouseDown:
            if gameplayInputEnabled {
                pendingEditActions.append(.remove)
            }
        case .rightMouseDown:
            if gameplayInputEnabled {
                pendingEditActions.append(.place)
            }
        case .flagsChanged:
            if gameplayInputEnabled {
                let shiftDown = event.modifierFlags.contains(.shift)
                playerInput.sprint = shiftDown
                playerInput.descend = shiftDown  // Shift = sprint on ground, descend in air
            }
        case .scrollWheel:
            // Scroll to cycle the hotbar selection. One step per wheel notch; a small
            // threshold keeps high-resolution trackpad scrolling from spinning too fast.
            if gameplayInputEnabled {
                let dy = event.scrollingDeltaY
                if dy > 0.5 {
                    pendingScrollSteps -= 1
                } else if dy < -0.5 {
                    pendingScrollSteps += 1
                }
            }
        default:
            break
        }
    }

    func consumeLookDelta() -> SIMD2<Float> {
        defer { pendingLookDelta = .zero }
        return pendingLookDelta
    }

    func consumeEditActions() -> [BlockEditAction] {
        defer { pendingEditActions.removeAll(keepingCapacity: true) }
        return pendingEditActions
    }

    func consumeMaterialDebugToggle() -> Bool {
        defer { pendingMaterialDebugToggle = false }
        return pendingMaterialDebugToggle
    }

    func consumePanelToggle() -> Bool {
        defer { pendingPanelToggle = false }
        return pendingPanelToggle
    }

    func consumeHUDToggle() -> Bool {
        defer { pendingHUDToggle = false }
        return pendingHUDToggle
    }

    func consumeBlockMaterialSelection() -> BlockMaterialType? {
        defer { pendingBlockMaterialSelection = nil }
        return pendingBlockMaterialSelection
    }

    func consumeEscape() -> Bool {
        defer { pendingEscape = false }
        return pendingEscape
    }

    func consumeFlyToggle() -> Bool {
        defer { pendingFlyToggle = false }
        return pendingFlyToggle
    }

    /// Net hotbar-cycle steps since the last frame (positive = next, negative = previous).
    func consumeMaterialCycle() -> Int {
        defer { pendingScrollSteps = 0 }
        return pendingScrollSteps
    }

    func cancelGameplayInput() {
        playerInput = PlayerInput()
        playerInput.sprint = false
        playerInput.descend = false
        pendingLookDelta = .zero
        pendingEditActions.removeAll(keepingCapacity: true)
    }

    private func setKeyState(for keyCode: UInt16, isPressed: Bool) {
        switch keyCode {
        case KeyCode.w:
            playerInput.moveForward = isPressed
        case KeyCode.s:
            playerInput.moveBackward = isPressed
        case KeyCode.a:
            playerInput.moveLeft = isPressed
        case KeyCode.d:
            playerInput.moveRight = isPressed
        case KeyCode.space:
            playerInput.jump = isPressed
        default:
            break
        }
    }

    private func blockMaterialShortcut(in event: NSEvent) -> BlockMaterialType? {
        guard
            let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let digit = characters.first?.wholeNumberValue,
            BlockMaterialType.allCases.indices.contains(digit - 1)
        else {
            return nil
        }

        return BlockMaterialType.allCases[digit - 1]
    }
}
