import simd

class Camera {
    var target:    SIMD3<Float> = .zero
    var azimuth:   Float = 0.0
    var elevation: Float = 0.3      // radians above horizon
    var radius:    Float = 15.0
    var zoomSpeed:   Float = 0.2
    var minRadius:   Float = 0.4

    var position: SIMD3<Float> {
        let x = radius * cos(elevation) * sin(azimuth)
        let y = radius * sin(elevation)
        let z = radius * cos(elevation) * cos(azimuth)
        return target + SIMD3<Float>(x, y, z)
    }

    var viewMatrix: matrix_float4x4 {
        let pos = position
        let f = normalize(target - pos)
        let r = normalize(cross(f, SIMD3<Float>(0, 1, 0)))
        let u = cross(r, f)
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
        // Clamp just shy of ±90° — at exactly ±π/2 the cross product with
        // worldUp degenerates (cos(elevation) == 0 → right vector is zero).
        // Everything in (-89.9°, +89.9°) works without any visible restriction.
        let limit: Float = .pi / 2 - 0.002
        elevation = max(-limit, min(limit, elevation - dy * 0.01))
    }

    func pan(dx: Float, dy: Float) {
        let pos = position
        let f = normalize(target - pos)
        let r = normalize(cross(f, SIMD3<Float>(0, 1, 0)))
        let u = cross(r, f)
        let scale = radius * 0.001
        target -= r * dx * scale
        target += u * dy * scale
    }

    func dolly(delta: Float) {
        radius = max(minRadius, radius - delta * zoomSpeed)
    }
}
