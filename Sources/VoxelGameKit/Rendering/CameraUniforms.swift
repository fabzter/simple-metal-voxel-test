import CoreGraphics
import simd

struct CameraUniforms {
    let projection: float4x4
    let view: float4x4

    init(
        camera: CameraState,
        projectionConfiguration: ProjectionConfiguration,
        drawableSize: CGSize
    ) {
        let aspect = Float(drawableSize.width / drawableSize.height)
        projection = float4x4.perspective(
            fov: projectionConfiguration.fieldOfViewDegrees * (.pi / 180.0),
            aspect: aspect,
            near: projectionConfiguration.nearClip,
            far: projectionConfiguration.farClip)
        view =
            float4x4(rotationX: camera.pitch)
            * float4x4(rotationY: camera.yaw)
            * float4x4(translation: -camera.position)
    }

    func rawValue(
        materialDebugMode: MaterialDebugMode,
        lodTintOverlayMode: LODTintOverlayMode,
        lodTintColor: SIMD4<Float>,
        highlightColor: SIMD4<Float>
    ) -> Uniforms {
        Uniforms(
            projection: projection,
            view: view,
            materialDebugMode: materialDebugMode.rawValue,
            lodTintOverlayMode: lodTintOverlayMode == .off ? 0 : 1,
            lodTintColor: lodTintColor,
            highlightColor: highlightColor)
    }
}
