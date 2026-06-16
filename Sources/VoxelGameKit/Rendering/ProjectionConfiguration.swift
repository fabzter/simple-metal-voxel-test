// Projection settings describe how the 3D world is projected onto the 2D screen.
//
// - `fieldOfViewDegrees` controls how wide the camera feels.
// - `nearClip` and `farClip` control which depth range is visible.
public struct ProjectionConfiguration: Sendable, Equatable {
    public var fieldOfViewDegrees: Float
    public var nearClip: Float
    public var farClip: Float

    public init(
        fieldOfViewDegrees: Float = 65.0,
        nearClip: Float = 0.1,
        farClip: Float = 1000.0
    ) {
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.nearClip = nearClip
        self.farClip = farClip
    }

    public static let `default` = ProjectionConfiguration()
}
