import simd

/// CPU-side mirror of the GaussianSplat C struct in ShaderTypes.h.
/// Field order and types must match exactly — the array is uploaded directly
/// to a MTLBuffer and read by the vertex shader without any conversion.
///
/// SIMD3<Float> is 16 bytes in Swift but 12 bytes in C (vector_float3),
/// so we use explicit Float fields to guarantee the layout is identical.
/// Total: 16 + 16 + 16 + 16 = 64 bytes.
struct GaussianSplatData {
    // position xyz + opacity — 16 bytes
    var posX, posY, posZ: Float
    var opacity: Float

    // rotation quaternion xyzw — 16 bytes
    var rotX, rotY, rotZ, rotW: Float

    // scale xyz + padding — 16 bytes
    var scaleX, scaleY, scaleZ: Float
    var _pad0: Float = 0

    // color rgb + padding — 16 bytes
    var colorR, colorG, colorB: Float
    var _pad1: Float = 0

    // MARK: - Convenience accessors

    var position: SIMD3<Float> {
        get { SIMD3(posX, posY, posZ) }
        set { posX = newValue.x; posY = newValue.y; posZ = newValue.z }
    }

    var rotation: SIMD4<Float> {
        get { SIMD4(rotX, rotY, rotZ, rotW) }
        set { rotX = newValue.x; rotY = newValue.y; rotZ = newValue.z; rotW = newValue.w }
    }

    var scale: SIMD3<Float> {
        get { SIMD3(scaleX, scaleY, scaleZ) }
        set { scaleX = newValue.x; scaleY = newValue.y; scaleZ = newValue.z }
    }

    var color: SIMD3<Float> {
        get { SIMD3(colorR, colorG, colorB) }
        set { colorR = newValue.x; colorG = newValue.y; colorB = newValue.z }
    }
}
