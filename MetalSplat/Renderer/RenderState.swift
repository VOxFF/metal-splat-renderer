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

    // Mesh pipeline — uses vertex descriptor, writes depth, no blending
    init(device: MTLDevice,
         mtkView: MTKView,
         material: Material,
         geometry: MeshGeometry) throws
    {
        let (ps, ds, ss) = try RenderState.buildPipeline(
            device: device,
            mtkView: mtkView,
            material: material,
            vertexDescriptor: geometry.mtlVertexDescriptor,
            blending: false,
            depthWrite: true)
        self.pipelineState    = ps
        self.depthStencilState = ds
        self.samplerState      = ss
    }

    // Splat pipeline — no vertex descriptor, no depth write, alpha blending
    init(device: MTLDevice,
         mtkView: MTKView,
         material: Material) throws
    {
        let (ps, ds, ss) = try RenderState.buildPipeline(
            device: device,
            mtkView: mtkView,
            material: material,
            vertexDescriptor: nil,
            blending: true,
            depthWrite: false)
        self.pipelineState    = ps
        self.depthStencilState = ds
        self.samplerState      = ss
    }

    // MARK: - Shared pipeline builder

    private static func buildPipeline(
        device: MTLDevice,
        mtkView: MTKView,
        material: Material,
        vertexDescriptor: MTLVertexDescriptor?,
        blending: Bool,
        depthWrite: Bool
    ) throws -> (MTLRenderPipelineState, MTLDepthStencilState, MTLSamplerState) {

        guard let library = device.makeDefaultLibrary() else {
            throw RenderStateError.libraryNotFound
        }
        guard let vfn = library.makeFunction(name: material.vertex_shader) else {
            throw RenderStateError.functionNotFound(name: material.vertex_shader)
        }
        guard let ffn = library.makeFunction(name: material.fragment_shader) else {
            throw RenderStateError.functionNotFound(name: material.fragment_shader)
        }

        let pDesc = MTLRenderPipelineDescriptor()
        pDesc.label                     = "Pipeline_\(material.vertex_shader)_\(material.fragment_shader)"
        pDesc.vertexFunction            = vfn
        pDesc.fragmentFunction          = ffn
        pDesc.vertexDescriptor          = vertexDescriptor
        pDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pDesc.rasterSampleCount         = mtkView.sampleCount
        pDesc.depthAttachmentPixelFormat   = mtkView.depthStencilPixelFormat
        pDesc.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat

        if blending {
            let ca = pDesc.colorAttachments[0]!
            ca.isBlendingEnabled             = true
            ca.rgbBlendOperation             = .add
            ca.alphaBlendOperation           = .add
            ca.sourceRGBBlendFactor          = .one               // pre-multiplied alpha
            ca.destinationRGBBlendFactor     = .oneMinusSourceAlpha
            ca.sourceAlphaBlendFactor        = .one
            ca.destinationAlphaBlendFactor   = .oneMinusSourceAlpha
        }

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pDesc)
        } catch {
            throw RenderStateError.pipelineCreationFailed(error)
        }

        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled  = depthWrite
        guard let dsState = device.makeDepthStencilState(descriptor: dsDesc) else {
            fatalError("Failed to create MTLDepthStencilState")
        }

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter    = .linear
        sampDesc.magFilter    = .linear
        sampDesc.mipFilter    = .nearest
        sampDesc.sAddressMode = .repeat
        sampDesc.tAddressMode = .repeat
        guard let ss = device.makeSamplerState(descriptor: sampDesc) else {
            fatalError("Failed to create MTLSamplerState")
        }

        return (pipelineState, dsState, ss)
    }
}

struct RenderStateKey: Hashable {
    let materialHash: Int
    let vertexDescriptorHash: Int  // 0 when absent (e.g. splats)

    init(material: Material, vertexDescriptor: MTLVertexDescriptor? = nil) {
        self.materialHash = material.hashValue()
        self.vertexDescriptorHash = vertexDescriptor?.hashValue() ?? 0
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
