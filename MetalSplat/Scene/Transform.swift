//
//  Transform.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/29/25.
//

import Foundation

import simd
import MetalKit  // for matrix helpers if you like

/// A simple transform with position, rotation (quaternion), and scale
class Transform {
    public var position: SIMD3<Float> = .zero
    public var rotation: simd_quatf = simd_quatf(angle: 0, axis: [0,0,1])
    public var scale:    SIMD3<Float> = SIMD3<Float>(1,1,1)
    
    /// Compose T * R * S
    public func matrix() -> matrix_float4x4 {
        let T = Transform.translation(position)
        let R = Transform.rotationMatrix(rotation)
        let S = Transform.scale(scale)
        return T * R * S
    }
    
    // MARK: — Static helpers
    
    static func translation(_ t: SIMD3<Float>) -> matrix_float4x4 {
        var M = matrix_identity_float4x4
        M.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        return M
    }

    static func scale(_ s: SIMD3<Float>) -> matrix_float4x4 {
        var M = matrix_identity_float4x4
        M.columns.0.x = s.x
        M.columns.1.y = s.y
        M.columns.2.z = s.z
        return M
    }

    static func rotationMatrix(_ q: simd_quatf) -> matrix_float4x4 {
        return simd_matrix4x4(q)
    }
}

/////////////
///
// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}


