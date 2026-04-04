//
//  RenderState.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/5/25.
//

import Metal
import MetalKit

enum RenderStateError: Error {
    case libraryNotFound
    case functionNotFound(name: String)
    case pipelineCreationFailed(Error)
}

/// A small helper that builds one pipeline state, one depth/stencil state, and one sampler,
/// given shader names + a vertex descriptor. You can then use `.pipelineState` when encoding.
class RenderState {
    
    /// The compiled render‐pipeline (vertex+fragment) with your vertex layout baked in.
    public let pipelineState: MTLRenderPipelineState

    /// A basic depth/stencil state (less‐compare + write‐enable).
    public let depthStencilState: MTLDepthStencilState

    /// A shared linear sampler (repeat addressing).
    public let samplerState: MTLSamplerState

    init(device: MTLDevice,
         mtkView: MTKView,
         material: Material,
         geometry: Geometry) throws
    {
        // 1) Load the default library:
        guard let library = device.makeDefaultLibrary() else {
            throw RenderStateError.libraryNotFound
        }

        // 2) Get function names from material:
        let vertexFunction = material.vertex_shader
        let fragmentFunction = material.fragment_shader

        guard let vfn = library.makeFunction(name: vertexFunction) else {
            throw RenderStateError.functionNotFound(name: vertexFunction)
        }
        guard let ffn = library.makeFunction(name: fragmentFunction) else {
            throw RenderStateError.functionNotFound(name: fragmentFunction)
        }

        // 3) Get vertex descriptor from geometry:
        let vertexDescriptor = geometry.mtlVertexDescriptor

        let pDesc = MTLRenderPipelineDescriptor()
        pDesc.label = "Pipeline_\(vertexFunction)_\(fragmentFunction)"
        pDesc.vertexFunction = vfn
        pDesc.fragmentFunction = ffn
        pDesc.vertexDescriptor = vertexDescriptor
        pDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pDesc.rasterSampleCount = mtkView.sampleCount
        pDesc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pDesc.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pDesc)
        } catch {
            throw RenderStateError.pipelineCreationFailed(error)
        }

        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        guard let dsState = device.makeDepthStencilState(descriptor: dsDesc) else {
            fatalError("Failed to create MTLDepthStencilState")
        }
        self.depthStencilState = dsState

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .linear
        sampDesc.magFilter = .linear
        sampDesc.mipFilter = .nearest
        sampDesc.sAddressMode = .repeat
        sampDesc.tAddressMode = .repeat
        guard let ss = device.makeSamplerState(descriptor: sampDesc) else {
            fatalError("Failed to create MTLSamplerState")
        }
        self.samplerState = ss
    }
}

struct RenderStateKey: Hashable {
    let materialHash: Int
    let vertexDescriptorHash: Int

    init(material: Material, vertexDescriptor: MTLVertexDescriptor) {
        self.materialHash = material.hashValue()
        self.vertexDescriptorHash = vertexDescriptor.hashValue()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(materialHash)
        hasher.combine(vertexDescriptorHash)
    }

    static func == (lhs: RenderStateKey, rhs: RenderStateKey) -> Bool {
        return lhs.materialHash == rhs.materialHash &&
               lhs.vertexDescriptorHash == rhs.vertexDescriptorHash
    }
}
