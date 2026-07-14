import Cocoa
import Metal
import Testing

@testable import VoxelDemo

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

    @MainActor
    @Test
    func controlsOverlayStartsVisibleForOnboarding() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device unavailable for onboarding overlay test.")
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        let view = try MetalView.make(frame: frame, deviceProvider: { device })
        let helpOverlay = view.subviews.compactMap { $0 as? HelpOverlayView }.first

        #expect(helpOverlay != nil)
        #expect(helpOverlay?.isHidden == false)
    }

    @Test
    func renderScaleShrinksDrawable() {
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        let halfScale = MetalView.makeDrawableSize(
            for: frame,
            backingScaleFactor: 2,
            renderScale: 0.5)
        let nativeScale = MetalView.makeDrawableSize(
            for: frame,
            backingScaleFactor: 2,
            renderScale: 1)
        let minimumSize = MetalView.makeDrawableSize(
            for: .zero,
            backingScaleFactor: 2,
            renderScale: 0.5)

        #expect(halfScale == CGSize(width: 1024, height: 768))
        #expect(nativeScale == CGSize(width: 2048, height: 1536))
        #expect(minimumSize.width >= 1)
        #expect(minimumSize.height >= 1)
    }
}
