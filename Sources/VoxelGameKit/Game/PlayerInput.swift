public struct PlayerInput: Sendable {
    public var moveForward: Bool
    public var moveBackward: Bool
    public var moveLeft: Bool
    public var moveRight: Bool
    public var jump: Bool

    public init(
        moveForward: Bool = false,
        moveBackward: Bool = false,
        moveLeft: Bool = false,
        moveRight: Bool = false,
        jump: Bool = false
    ) {
        self.moveForward = moveForward
        self.moveBackward = moveBackward
        self.moveLeft = moveLeft
        self.moveRight = moveRight
        self.jump = jump
    }
}
