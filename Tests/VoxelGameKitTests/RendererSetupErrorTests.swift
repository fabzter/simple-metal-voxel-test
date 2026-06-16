import Foundation
import Testing

@testable import VoxelGameKit

struct RendererSetupErrorTests {
    @Test
    func wrappedShaderLibraryErrorKeepsContext() {
        let wrapped = NSError(
            domain: "ShaderTests", code: 7,
            userInfo: [
                NSLocalizedDescriptionKey: "missing default library"
            ])

        let error = RendererSetupError.shaderLibraryUnavailable(wrapped)
        #expect(error.localizedDescription.contains("missing default library"))
    }

    @Test
    func meshBufferErrorIsReadable() {
        let error = RendererSetupError.meshBufferUnavailable
        #expect(error.localizedDescription == "Failed to allocate the world mesh buffer.")
    }
}
