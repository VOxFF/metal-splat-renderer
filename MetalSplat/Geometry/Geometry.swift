//
//  Geometry.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/10/25.
//

import MetalKit

protocol Geometry: AnyObject {
    /// Vertex descriptor used to build the pipeline state + cache key. Nil for splats.
    var vertexDescriptor: MTLVertexDescriptor? { get }

    /// Builds the appropriate RenderState for this geometry type.
    func makeRenderState(device: MTLDevice, mtkView: MTKView, material: Material) throws -> RenderState

    /// Full draw setup (pipeline, uniforms, cull mode) + calls encodeDraw.
    func draw(encoder: MTLRenderCommandEncoder, context: RenderContext)

    /// Geometry-specific primitive encoding only — bind buffers + issue draw call.
    func encodeDraw(encoder: MTLRenderCommandEncoder)
}

protocol MeshGeometry: Geometry {
    var mesh: MTKMesh { get }
    var mtlVertexDescriptor: MTLVertexDescriptor { get }
}

extension MeshGeometry {
    var vertexDescriptor: MTLVertexDescriptor? { mtlVertexDescriptor }

    func makeRenderState(device: MTLDevice, mtkView: MTKView, material: Material) throws -> RenderState {
        try RenderState(device: device, mtkView: mtkView, material: material, geometry: self)
    }

    func draw(encoder: MTLRenderCommandEncoder, context: RenderContext) {
        encoder.pushDebugGroup("Draw Mesh")
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setRenderPipelineState(context.renderState.pipelineState)
        encoder.setDepthStencilState(context.renderState.depthStencilState)

        var u = Uniforms(projectionMatrix: context.projectionMatrix,
                         modelViewMatrix: simd_mul(context.viewMatrix, context.nodeWorldTM))
        encoder.setVertexBytes(&u, length: MemoryLayout<Uniforms>.size,
                               index: Int(BufferIndex.uniforms.rawValue))
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.size,
                                 index: Int(BufferIndex.uniforms.rawValue))

        for (slot, tex) in context.textures {
            encoder.setFragmentTexture(tex, index: slot.rawValue)
        }

        encodeDraw(encoder: encoder)
        encoder.popDebugGroup()
    }
}

protocol SplatGeometry: Geometry {
    var splatCount: Int { get }
    var splatBuffer: MTLBuffer { get }
    var sortedIndexBuffer: MTLBuffer { get }
    func sortSplats(cameraPosition: SIMD3<Float>)
}

extension SplatGeometry {
    var vertexDescriptor: MTLVertexDescriptor? { nil }

    func makeRenderState(device: MTLDevice, mtkView: MTKView, material: Material) throws -> RenderState {
        try RenderState(device: device, mtkView: mtkView, material: material)
    }
}
