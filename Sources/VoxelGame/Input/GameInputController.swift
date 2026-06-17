import Cocoa
import VoxelGameKit
import simd

@MainActor
final class GameInputController {
    private var playerInput = PlayerInput()
    private var pendingLookDelta = SIMD2<Float>(repeating: 0)
    private var pendingEditActions: [BlockEditAction] = []

    var currentInput: PlayerInput {
        playerInput
    }

    func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            setKeyState(for: event.keyCode, isPressed: true)
        case .keyUp:
            setKeyState(for: event.keyCode, isPressed: false)
        case .mouseMoved:
            pendingLookDelta += SIMD2(Float(event.deltaX), Float(event.deltaY))
        case .leftMouseDown:
            pendingEditActions.append(.remove)
        case .rightMouseDown:
            pendingEditActions.append(.place)
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
}
