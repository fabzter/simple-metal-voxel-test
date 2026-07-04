import Cocoa
import Testing
import VoxelGameKit

@testable import VoxelGame

struct GameInputControllerTests {
    @MainActor
    @Test
    func f1TogglesHUDEvenWhenGameplayInputIsDisabled() throws {
        let controller = GameInputController()
        let event = try makeKeyDownEvent(
            characters: String(UnicodeScalar(NSF1FunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSF1FunctionKey)!),
            keyCode: 122)

        controller.handle(event, gameplayInputEnabled: false)

        #expect(controller.consumeHUDToggle())
        #expect(!controller.consumeHUDToggle())
    }

    @MainActor
    @Test
    func escapeIsConsumedEvenWhenGameplayInputIsDisabled() throws {
        let controller = GameInputController()
        let event = try makeKeyDownEvent(
            characters: "", charactersIgnoringModifiers: "", keyCode: 53)

        controller.handle(event, gameplayInputEnabled: false)

        #expect(controller.consumeEscape())
        #expect(!controller.consumeEscape())
    }

    @MainActor
    @Test
    func digitShortcutSelectsMatchingBlockMaterial() throws {
        let controller = GameInputController()
        let event = try makeKeyDownEvent(
            characters: "5", charactersIgnoringModifiers: "5", keyCode: 30)

        controller.handle(event, gameplayInputEnabled: true)

        #expect(controller.consumeBlockMaterialSelection() == .snow)
        #expect(controller.consumeBlockMaterialSelection() == nil)
    }

    @MainActor
    @Test
    func digitShortcutDoesNothingWhenGameplayInputIsDisabled() throws {
        let controller = GameInputController()
        let event = try makeKeyDownEvent(
            characters: "2", charactersIgnoringModifiers: "2", keyCode: 19)

        controller.handle(event, gameplayInputEnabled: false)

        #expect(controller.consumeBlockMaterialSelection() == nil)
    }

    @MainActor
    @Test
    func keyUpClearsMovementEvenWhenGameplayInputIsDisabled() throws {
        let controller = GameInputController()
        let keyDown = try makeKeyDownEvent(
            characters: "w", charactersIgnoringModifiers: "w", keyCode: 13)
        let keyUp = try makeKeyUpEvent(
            characters: "w", charactersIgnoringModifiers: "w", keyCode: 13)

        controller.handle(keyDown, gameplayInputEnabled: true)
        #expect(controller.currentInput.moveForward)

        controller.handle(keyUp, gameplayInputEnabled: false)
        #expect(!controller.currentInput.moveForward)
    }

    @MainActor
    @Test
    func cancelGameplayInputClearsMovementAndPendingEdits() throws {
        let controller = GameInputController()
        let keyDown = try makeKeyDownEvent(
            characters: "d", charactersIgnoringModifiers: "d", keyCode: 2)
        let removeEvent = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1))

        controller.handle(keyDown, gameplayInputEnabled: true)
        controller.handle(removeEvent, gameplayInputEnabled: true)

        controller.cancelGameplayInput()

        #expect(!controller.currentInput.moveRight)
        #expect(controller.consumeEditActions().isEmpty)
    }

    @MainActor
    private func makeKeyDownEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16
    ) throws -> NSEvent {
        try makeKeyEvent(
            type: .keyDown,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            keyCode: keyCode)
    }

    @MainActor
    private func makeKeyUpEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16
    ) throws -> NSEvent {
        try makeKeyEvent(
            type: .keyUp,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            keyCode: keyCode)
    }

    @MainActor
    private func makeKeyEvent(
        type: NSEvent.EventType,
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isARepeat: false,
                keyCode: keyCode))
    }
}
