import Cocoa
import Testing

@testable import VoxelGame

struct MetalViewStartupTests {
    @MainActor
    @Test
    func missingMetalProviderThrowsReadableError() {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 240)

        do {
            _ = try MetalView.make(frame: frame, deviceProvider: { nil })
            Issue.record("Expected MetalView.make to throw when no Metal device is available.")
        } catch let error as MetalViewError {
            #expect(error == .metalUnavailable)
            #expect(error.errorDescription == "Metal is not supported on this device.")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
