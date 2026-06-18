import Cocoa
import VoxelGameKit
import simd

@MainActor
final class GameInputController {
    private var playerInput = PlayerInput()
    private var pendingLookDelta = SIMD2<Float>(repeating: 0)
    private var pendingEditActions: [BlockEditAction] = []
    private var pendingMaterialDebugToggle = false
    private var pendingPanelToggle = false
    private var pendingHUDToggle = false
    private var pendingBlockMaterialSelection: BlockMaterialType?

    var currentInput: PlayerInput {
        playerInput
    }

    func handle(_ event: NSEvent, gameplayInputEnabled: Bool) {
        switch event.type {
        case .keyDown:
            if event.keyCode == 48 {  // Tab
                pendingPanelToggle = true
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
            if gameplayInputEnabled {
                setKeyState(for: event.keyCode, isPressed: false)
            }
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

    private func setKeyState(for keyCode: UInt16, isPressed: Bool) {
        switch keyCode {
        case 13:
            playerInput.moveForward = isPressed
        case 1:
            playerInput.moveBackward = isPressed
        case 0:
            playerInput.moveLeft = isPressed
        case 2:
            playerInput.moveRight = isPressed
        case 49:
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
