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

enum ShaderLibraryError: LocalizedError {
    case missingLibrary

    var errorDescription: String? {
        switch self {
        case .missingLibrary:
            return "The compiled Metal shader library could not be found in the app bundle."
        }
    }
}
