import simd

extension float4x4 {
    init(rotationX: Float) {
        let c = cos(rotationX)
        let s = sin(rotationX)

        self.init(
            columns: (
                SIMD4(1, 0, 0, 0),
                SIMD4(0, c, s, 0),
                SIMD4(0, -s, c, 0),
                SIMD4(0, 0, 0, 1)
            ))
    }

    init(rotationY: Float) {
        let c = cos(rotationY)
        let s = sin(rotationY)

        self.init(
            columns: (
                SIMD4(c, 0, -s, 0),
                SIMD4(0, 1, 0, 0),
                SIMD4(s, 0, c, 0),
                SIMD4(0, 0, 0, 1)
            ))
    }

    init(translation t: SIMD3<Float>) {
        self.init(
            columns: (
                SIMD4(1, 0, 0, 0),
                SIMD4(0, 1, 0, 0),
                SIMD4(0, 0, 1, 0),
                SIMD4(t.x, t.y, t.z, 1)
            ))
    }

    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let yScale = 1 / tan(fov * 0.5)
        let xScale = yScale / aspect
        let zScale = far / (near - far)
        let wzScale = (near * far) / (near - far)

        return float4x4(
            columns: (
                SIMD4(xScale, 0, 0, 0),
                SIMD4(0, yScale, 0, 0),
                SIMD4(0, 0, zScale, -1),
                SIMD4(0, 0, wzScale, 0)
            ))
    }
}
