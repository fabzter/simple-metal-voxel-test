import CoreGraphics
import simd

struct CameraUniforms {
    let projection: float4x4
    let view: float4x4

    init(camera: CameraState, drawableSize: CGSize) {
        let aspect = Float(drawableSize.width / drawableSize.height)
        projection = float4x4.perspective(
            fov: 65.0 * (.pi / 180.0),
            aspect: aspect,
            near: 0.1,
            far: 1000.0)
        view =
            float4x4(rotationX: camera.pitch)
            * float4x4(rotationY: camera.yaw)
            * float4x4(translation: -camera.position)
    }

    var rawValue: Uniforms {
        Uniforms(projection: projection, view: view)
    }
}
