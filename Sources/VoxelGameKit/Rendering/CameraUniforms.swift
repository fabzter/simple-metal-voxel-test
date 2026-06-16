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

    var rawValue: Uniforms {
        Uniforms(projection: projection, view: view)
    }
}
