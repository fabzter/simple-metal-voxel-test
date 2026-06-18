import Foundation

// These are startup-time errors: they happen while wiring Metal together before the first
// frame can be drawn. The app surfaces them to the user instead of crashing blindly.
public enum RendererSetupError: LocalizedError {
    case commandQueueUnavailable
    case meshBufferUnavailable
    case materialAtlasUnavailable
    case highlightBufferUnavailable
    case shaderLibraryUnavailable(Error)
    case pipelineStateUnavailable(Error)
    case depthStateUnavailable

    public var errorDescription: String? {
        switch self {
        case .commandQueueUnavailable:
            return "Failed to create the Metal command queue."
        case .meshBufferUnavailable:
            return "Failed to allocate the world mesh buffer."
        case .materialAtlasUnavailable:
            return "Failed to create the in-memory material atlas texture."
        case .highlightBufferUnavailable:
            return "Failed to allocate the selection highlight buffer."
        case .shaderLibraryUnavailable(let error):
            return "Failed to load the Metal shader library: \(error.localizedDescription)"
        case .pipelineStateUnavailable(let error):
            return "Failed to create the Metal render pipeline: \(error.localizedDescription)"
        case .depthStateUnavailable:
            return "Failed to create the Metal depth state."
        }
    }
}
