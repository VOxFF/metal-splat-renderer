//
//  Geometry.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/10/25.
//

import MetalKit

protocol Geometry: AnyObject {
    func encodeDraw(encoder: MTLRenderCommandEncoder)
}

protocol MeshGeometry: Geometry {
    var mesh: MTKMesh { get }
    var mtlVertexDescriptor: MTLVertexDescriptor { get }
}

protocol SplatGeometry: Geometry {
    var splatCount: Int { get }
    var splatBuffer: MTLBuffer { get }
    var sortedIndexBuffer: MTLBuffer { get }
    func sortSplats(cameraPosition: SIMD3<Float>)
}
