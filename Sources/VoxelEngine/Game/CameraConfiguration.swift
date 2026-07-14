// Camera settings are grouped here so the “feel” of looking around is easy to tweak
// without hunting through player or renderer code.
public struct CameraConfiguration: Sendable, Equatable {
    public var eyeHeight: Float
    public var lookSensitivity: Float
    /// Some players expect flight-stick pitch where moving the mouse up looks down.
    public var invertLookY: Bool
    public var minimumPitch: Float
    public var maximumPitch: Float

    public init(
        eyeHeight: Float = 1.6,
        lookSensitivity: Float = 0.005,
        invertLookY: Bool = false,
        minimumPitch: Float = -1.5,
        maximumPitch: Float = 1.5
    ) {
        self.eyeHeight = eyeHeight
        self.lookSensitivity = lookSensitivity
        self.invertLookY = invertLookY
        self.minimumPitch = minimumPitch
        self.maximumPitch = maximumPitch
    }

    public static let `default` = CameraConfiguration()
}
