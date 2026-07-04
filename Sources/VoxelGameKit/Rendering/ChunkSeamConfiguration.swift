enum ChunkBoundaryDirection: CaseIterable, Hashable {
    case positiveX
    case negativeX
    case positiveY
    case negativeY
    case positiveZ
    case negativeZ
}

struct ChunkSeamConfiguration: Hashable {
    var positiveXFinerStride: Int?
    var negativeXFinerStride: Int?
    var positiveYFinerStride: Int?
    var negativeYFinerStride: Int?
    var positiveZFinerStride: Int?
    var negativeZFinerStride: Int?

    static let none = ChunkSeamConfiguration()

    func finerStride(for direction: ChunkBoundaryDirection) -> Int? {
        switch direction {
        case .positiveX: positiveXFinerStride
        case .negativeX: negativeXFinerStride
        case .positiveY: positiveYFinerStride
        case .negativeY: negativeYFinerStride
        case .positiveZ: positiveZFinerStride
        case .negativeZ: negativeZFinerStride
        }
    }
}
