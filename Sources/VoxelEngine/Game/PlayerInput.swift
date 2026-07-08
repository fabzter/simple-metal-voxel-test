public struct PlayerInput: Sendable {
    public var moveForward: Bool
    public var moveBackward: Bool
    public var moveLeft: Bool
    public var moveRight: Bool
    public var jump: Bool
    public var sprint: Bool
    public var descend: Bool  // Only meaningful while flying; Shift serves double duty

    public init(
        moveForward: Bool = false,
        moveBackward: Bool = false,
        moveLeft: Bool = false,
        moveRight: Bool = false,
        jump: Bool = false,
        sprint: Bool = false,
        descend: Bool = false
    ) {
        self.moveForward = moveForward
        self.moveBackward = moveBackward
        self.moveLeft = moveLeft
        self.moveRight = moveRight
        self.jump = jump
        self.sprint = sprint
        self.descend = descend
    }
}
