import simd

class Camera {
    var target:    SIMD3<Float> = .zero
    var azimuth:   Float = 0.0
    var elevation: Float = 0.3      // radians above horizon
    var radius:    Float = 15.0

    var position: SIMD3<Float> {
        let x = radius * cos(elevation) * sin(azimuth)
        let y = radius * sin(elevation)
        let z = radius * cos(elevation) * cos(azimuth)
        return target + SIMD3<Float>(x, y, z)
    }

    var viewMatrix: matrix_float4x4 {
        let pos = position
        let f = normalize(target - pos)                    // forward
        let r = normalize(cross(f, SIMD3<Float>(0,1,0)))  // right
        let u = cross(r, f)                                // up (reorthogonalized)
        return matrix_float4x4(columns: (
            SIMD4<Float>( r.x,  u.x, -f.x, 0),
            SIMD4<Float>( r.y,  u.y, -f.y, 0),
            SIMD4<Float>( r.z,  u.z, -f.z, 0),
            SIMD4<Float>(-dot(r, pos), -dot(u, pos), dot(f, pos), 1)
        ))
    }

    // MARK: - Manipulation

    func orbit(dx: Float, dy: Float) {
        azimuth   += dx * 0.01
        let minEl: Float = -.pi / 2 + 0.01
        let maxEl: Float =  .pi / 2 - 0.01
        elevation = min(maxEl, max(minEl, elevation - dy * 0.01))
    }

    func pan(dx: Float, dy: Float) {
        let pos = position
        let f = normalize(target - pos)
        let r = normalize(cross(f, SIMD3<Float>(0,1,0)))
        let u = cross(r, f)
        let scale = radius * 0.001
        target -= r * dx * scale
        target += u * dy * scale
    }

    func dolly(delta: Float) {
        radius = max(0.5, radius - delta * 0.5)
    }
}
