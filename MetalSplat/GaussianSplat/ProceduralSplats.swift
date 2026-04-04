import simd

enum ProceduralSplats {

    /// A 3D grid of splats with rainbow colors.
    static func grid(count: Int = 5, spacing: Float = 1.2, scale: Float = 0.15) -> [GaussianSplatData] {
        var splats: [GaussianSplatData] = []
        splats.reserveCapacity(count * count * count)
        let half = Float(count - 1) * spacing * 0.5

        for ix in 0..<count {
            for iy in 0..<count {
                for iz in 0..<count {
                    let x = Float(ix) * spacing - half
                    let y = Float(iy) * spacing - half
                    let z = Float(iz) * spacing - half

                    // hue varies along x axis, full saturation and value
                    let h = Float(ix) / Float(count - 1)
                    let (r, g, b) = hsv(h, 1.0, 1.0)

                    splats.append(GaussianSplatData(
                        posX: x, posY: y, posZ: z,
                        opacity: 0.9,
                        rotX: 0, rotY: 0, rotZ: 0, rotW: 1,  // identity quaternion
                        scaleX: scale, scaleY: scale, scaleZ: scale,
                        colorR: r, colorG: g, colorB: b
                    ))
                }
            }
        }
        return splats
    }

    // HSV → RGB (H in [0,1])
    private static func hsv(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
        let i = Int(h * 6)
        let f = h * 6 - Float(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
