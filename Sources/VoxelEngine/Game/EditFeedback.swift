public struct EditFeedback {
    public enum Kind: Sendable {
        case remove
        case place
    }

    public var kind: Kind
    public var hit: VoxelRaycastHit
    public var remainingTime: Float

    public init(kind: Kind, hit: VoxelRaycastHit, remainingTime: Float = 0.18) {
        self.kind = kind
        self.hit = hit
        self.remainingTime = remainingTime
    }
}
