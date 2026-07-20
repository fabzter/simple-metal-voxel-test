import CoreGraphics
import Testing
import simd

@testable import VoxelEngine

struct FrustumCullerTests {
    @Test
    func keepsBoundsInFrontOfCamera() {
        let camera = CameraState(position: .zero, yaw: 0, pitch: 0)
        let uniforms = CameraUniforms(
            camera: camera,
            projectionConfiguration: .default,
            drawableSize: CGSize(width: 1024, height: 768))
        let culler = FrustumCuller(viewProjectionMatrix: uniforms.projection * uniforms.view)

        let visible = AxisAlignedBoundingBox(
            minimum: SIMD3<Float>(-0.5, -0.5, -5),
            maximum: SIMD3<Float>(0.5, 0.5, -4))

        #expect(culler.isVisible(bounds: visible))
    }

    @Test
    func cullsBoundsBehindCamera() {
        let camera = CameraState(position: .zero, yaw: 0, pitch: 0)
        let uniforms = CameraUniforms(
            camera: camera,
            projectionConfiguration: .default,
            drawableSize: CGSize(width: 1024, height: 768))
        let culler = FrustumCuller(viewProjectionMatrix: uniforms.projection * uniforms.view)

        let invisible = AxisAlignedBoundingBox(
            minimum: SIMD3<Float>(-0.5, -0.5, 4),
            maximum: SIMD3<Float>(0.5, 0.5, 5))

        #expect(!culler.isVisible(bounds: invisible))
    }

    @Test
    func cullsGeometryCloserThanNearClip() {
        // `float4x4.perspective` is Metal [0,1] clip space, whose near plane is row r2 (not
        // the OpenGL r3+r2 form). Geometry nearer than nearClip (0.1) must be culled.
        let camera = CameraState(position: .zero, yaw: 0, pitch: 0)
        let uniforms = CameraUniforms(
            camera: camera,
            projectionConfiguration: .default,
            drawableSize: CGSize(width: 1024, height: 768))
        let culler = FrustumCuller(viewProjectionMatrix: uniforms.projection * uniforms.view)
        // In front of the camera (-z) but nearer than nearClip (0.1) -> must be culled.
        let tooClose = AxisAlignedBoundingBox(
            minimum: SIMD3<Float>(-0.01, -0.01, -0.08),
            maximum: SIMD3<Float>(0.01, 0.01, -0.06))
        #expect(!culler.isVisible(bounds: tooClose))
    }
}
