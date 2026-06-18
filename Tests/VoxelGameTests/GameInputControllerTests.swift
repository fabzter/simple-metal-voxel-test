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
    private func makeKeyDownEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
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
