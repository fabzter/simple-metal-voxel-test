public struct RenderDebugSettings: Sendable {
    public var materialMode: MaterialDebugMode
    public var lodTintOverlayMode: LODTintOverlayMode
    public var frustumCullingEnabled: Bool
    public var occlusionCullingEnabled: Bool
    public var lodEnabled: Bool

    public init(
        materialMode: MaterialDebugMode = .hybrid,
        lodTintOverlayMode: LODTintOverlayMode = .off,
        frustumCullingEnabled: Bool = true,
        occlusionCullingEnabled: Bool = true,
        lodEnabled: Bool = true
    ) {
        self.materialMode = materialMode
        self.lodTintOverlayMode = lodTintOverlayMode
        self.frustumCullingEnabled = frustumCullingEnabled
        self.occlusionCullingEnabled = occlusionCullingEnabled
        self.lodEnabled = lodEnabled
    }
}
