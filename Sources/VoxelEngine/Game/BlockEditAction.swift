// User-triggered block editing operations.
//
// - `.remove` deletes the first solid voxel hit by the camera ray.
// - `.place` adds a voxel into the empty cell just before the hit voxel.
public enum BlockEditAction: Sendable {
    case remove
    case place
}
