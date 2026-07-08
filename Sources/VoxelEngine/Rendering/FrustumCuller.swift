import simd

struct FrustumCuller {
    private let planes: [SIMD4<Float>]

    init(viewProjectionMatrix: float4x4) {
        let r0 = SIMD4(
            viewProjectionMatrix.columns.0.x,
            viewProjectionMatrix.columns.1.x,
            viewProjectionMatrix.columns.2.x,
            viewProjectionMatrix.columns.3.x)
        let r1 = SIMD4(
            viewProjectionMatrix.columns.0.y,
            viewProjectionMatrix.columns.1.y,
            viewProjectionMatrix.columns.2.y,
            viewProjectionMatrix.columns.3.y)
        let r2 = SIMD4(
            viewProjectionMatrix.columns.0.z,
            viewProjectionMatrix.columns.1.z,
            viewProjectionMatrix.columns.2.z,
            viewProjectionMatrix.columns.3.z)
        let r3 = SIMD4(
            viewProjectionMatrix.columns.0.w,
            viewProjectionMatrix.columns.1.w,
            viewProjectionMatrix.columns.2.w,
            viewProjectionMatrix.columns.3.w)

        planes = [
            Self.normalizePlane(r3 + r0),
            Self.normalizePlane(r3 - r0),
            Self.normalizePlane(r3 + r1),
            Self.normalizePlane(r3 - r1),
            Self.normalizePlane(r3 + r2),
            Self.normalizePlane(r3 - r2),
        ]
    }

    func isVisible(bounds: AxisAlignedBoundingBox) -> Bool {
        for plane in planes {
            let normal = SIMD3<Float>(plane.x, plane.y, plane.z)
            let positiveVertex = SIMD3<Float>(
                plane.x >= 0 ? bounds.maximum.x : bounds.minimum.x,
                plane.y >= 0 ? bounds.maximum.y : bounds.minimum.y,
                plane.z >= 0 ? bounds.maximum.z : bounds.minimum.z)

            if dot(normal, positiveVertex) + plane.w < 0 {
                return false
            }
        }

        return true
    }

    private static func normalizePlane(_ plane: SIMD4<Float>) -> SIMD4<Float> {
        let normalLength = simd_length(SIMD3<Float>(plane.x, plane.y, plane.z))
        guard normalLength > 0.0001 else {
            return plane
        }
        return plane / normalLength
    }
}

struct AxisAlignedBoundingBox {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>
}
