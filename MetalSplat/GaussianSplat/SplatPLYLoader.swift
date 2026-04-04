import Foundation

enum SplatPLYError: Error {
    case fileNotFound
    case invalidHeader
    case unsupportedFormat       // only binary_little_endian is supported
    case missingProperty(String)
}

struct SplatPLYLoader {

    // DC spherical harmonic coefficient — converts f_dc to linear RGB
    private static let SH_C0: Float = 0.28209479177387814

    static func load(url: URL) throws -> [GaussianSplatData] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // --- Parse header ---------------------------------------------------

        // Support both Unix and Windows line endings
        let headerEnd = data.range(of: Data("end_header\n".utf8))
                     ?? data.range(of: Data("end_header\r\n".utf8))
        guard let headerRange = headerEnd else { throw SplatPLYError.invalidHeader }

        guard let header = String(data: data[..<headerRange.lowerBound], encoding: .ascii) else {
            throw SplatPLYError.invalidHeader
        }
        let bodyStart = headerRange.upperBound

        let lines = header.components(separatedBy: .newlines)

        // Require binary little-endian
        guard lines.contains(where: { $0.contains("binary_little_endian") }) else {
            throw SplatPLYError.unsupportedFormat
        }

        // Vertex count
        guard let vertexLine = lines.first(where: { $0.hasPrefix("element vertex") }),
              let splatCount = Int(vertexLine.components(separatedBy: " ").last ?? "") else {
            throw SplatPLYError.invalidHeader
        }

        // Build property name → byte offset map
        var propOffset: [String: Int] = [:]
        var cursor = 0
        for line in lines {
            let parts = line.components(separatedBy: " ")
            if parts.first == "property" && parts.count == 3 {
                let type = parts[1]
                let name = parts[2]
                propOffset[name] = cursor
                switch type {
                case "float", "int", "uint": cursor += 4
                case "double":               cursor += 8
                case "uchar", "uint8":       cursor += 1
                case "short", "ushort":      cursor += 2
                default:                     cursor += 4
                }
            }
        }
        let vertexStride = cursor

        // Require the properties 3DGS PLY files must have
        func offset(of name: String) throws -> Int {
            guard let o = propOffset[name] else { throw SplatPLYError.missingProperty(name) }
            return o
        }

        let oX       = try offset(of: "x")
        let oY       = try offset(of: "y")
        let oZ       = try offset(of: "z")
        let oOpacity = try offset(of: "opacity")
        let oRot0    = try offset(of: "rot_0")   // w in 3DGS convention
        let oRot1    = try offset(of: "rot_1")   // x
        let oRot2    = try offset(of: "rot_2")   // y
        let oRot3    = try offset(of: "rot_3")   // z
        let oScale0  = try offset(of: "scale_0")
        let oScale1  = try offset(of: "scale_1")
        let oScale2  = try offset(of: "scale_2")
        let oFdc0    = try offset(of: "f_dc_0")
        let oFdc1    = try offset(of: "f_dc_1")
        let oFdc2    = try offset(of: "f_dc_2")

        // --- Read binary body -----------------------------------------------

        var splats = [GaussianSplatData]()
        splats.reserveCapacity(splatCount)

        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: bodyStart)

            for i in 0..<splatCount {
                let v = base.advanced(by: i * vertexStride)

                func f(_ off: Int) -> Float {
                    v.advanced(by: off).loadUnaligned(as: Float.self)
                }

                // Sigmoid on raw opacity
                let opacity = 1.0 / (1.0 + exp(-f(oOpacity)))

                // Quaternion: 3DGS stores (w,x,y,z); we store (x,y,z,w)
                // Normalize to guard against non-unit quats in the file
                let qw = f(oRot0); let qx = f(oRot1)
                let qy = f(oRot2); let qz = f(oRot3)
                let qLen = sqrt(qw*qw + qx*qx + qy*qy + qz*qz)

                // Exp on log-space scales
                let sx = exp(f(oScale0))
                let sy = exp(f(oScale1))
                let sz = exp(f(oScale2))

                // DC SH → linear RGB: color = clamp(0.5 + SH_C0 * f_dc, 0, 1)
                let cr = min(max(0.5 + SH_C0 * f(oFdc0), 0), 1)
                let cg = min(max(0.5 + SH_C0 * f(oFdc1), 0), 1)
                let cb = min(max(0.5 + SH_C0 * f(oFdc2), 0), 1)

                splats.append(GaussianSplatData(
                    posX: f(oX), posY: f(oY), posZ: f(oZ),
                    opacity: opacity,
                    rotX: qx/qLen, rotY: qy/qLen, rotZ: qz/qLen, rotW: qw/qLen,
                    scaleX: sx, scaleY: sy, scaleZ: sz,
                    colorR: cr, colorG: cg, colorB: cb
                ))
            }
        }

        return splats
    }
}
