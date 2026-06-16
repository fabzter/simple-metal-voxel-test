import Foundation
import Metal

struct ShaderLibrary {
    let library: MTLLibrary

    init(device: MTLDevice) throws {
        guard
            let shaderURL = Bundle.module.url(
                forResource: "VoxelShaders", withExtension: "metallib")
        else {
            throw ShaderLibraryError.missingLibrary
        }

        library = try device.makeLibrary(URL: shaderURL)
    }
}

enum ShaderLibraryError: Error {
    case missingLibrary
}
