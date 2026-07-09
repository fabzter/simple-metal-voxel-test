import CoreGraphics
import simd

struct CameraUniforms {
    let projection: float4x4
    let view: float4x4
    let cameraPosition: SIMD3<Float>
    /// Inverse of `projection * view`. The sky shader multiplies clip-space corners by
    /// this to recover a world-space ray for each pixel, cheaply turning the depth-less
    /// background into a directional gradient.
    let inverseViewProjection: float4x4
    let sky: SkyConfiguration

    init(
        camera: CameraState,
        projectionConfiguration: ProjectionConfiguration,
        drawableSize: CGSize,
        sky: SkyConfiguration = .default
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
        cameraPosition = camera.position
        inverseViewProjection = simd_inverse(projection * view)
        self.sky = sky
    }

    func rawValue(
        materialDebugMode: MaterialDebugMode,
        lodTintOverlayMode: LODTintOverlayMode,
        lodTintColor: SIMD4<Float>,
        highlightColor: SIMD4<Float>,
        fadeThreshold: Float
    ) -> Uniforms {
        Uniforms(
            projection: projection,
            view: view,
            materialDebugMode: materialDebugMode.rawValue,
            lodTintOverlayMode: lodTintOverlayMode == .off ? 0 : 1,
            lodTintColor: lodTintColor,
            highlightColor: highlightColor,
            fadeThreshold: fadeThreshold,
            // Atmosphere: pack the SkyConfiguration into the shader's float4 slots. The
            // unused `w` lanes are padding kept for 16-byte alignment.
            inverseViewProjection: inverseViewProjection,
            cameraPositionAndFog: SIMD4<Float>(cameraPosition, sky.fogDensity),
            sunDirection: SIMD4<Float>(sky.sunDirection, 0),
            sunColor: SIMD4<Float>(sky.sunColor, 0),
            skyZenithColor: SIMD4<Float>(sky.zenithColor, 0),
            skyHorizonColor: SIMD4<Float>(sky.horizonColor, 0),
            groundColor: SIMD4<Float>(sky.groundColor, 0))
    }
}
