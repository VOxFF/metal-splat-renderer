//
//  Box.swift
//  LearningMetal
//
//   Created by Volodymyr Dubovyi on 6/5/25.
//

import MetalKit

/// A helper class that encapsulates “build a box mesh” logic.
/// After init, you can grab `mesh` and `vertexDescriptor` from an instance of Box.
class Box: MeshGeometry {
    /// The MetalKit mesh that can be drawn by the renderer.
    public let mesh: MTKMesh

    /// The Metal‐level vertex descriptor used when creating the mesh,
    /// which must also be passed into the render pipeline's vertex descriptor.
    public let mtlVertexDescriptor: MTLVertexDescriptor

    /// Create a new Box by building a 4×4×4 box subdivided 2×2×2.
    /// - Parameters:
    ///   - device:   The MTLDevice to use for buffer allocation.
    ///   - scale:    Optional uniform scale of the box dimensions (default: 4.0).
    ///   - segments: How many segments per axis (default: 2,2,2).
    /// - Throws: RendererError.badVertexDescriptor if the descriptor conversion fails,
    ///           or any MTKMesh/MDLMesh initialization error.
    init(device: MTLDevice,
         scale: Float = 4.0,
         segments: SIMD3<UInt32> = SIMD3<UInt32>(2, 2, 2))
    throws
    {
        // 1) Build a Metal‐level MTLVertexDescriptor describing how your shaders will interpret layout.
        //    You must match these attribute‐indices with what your Metal shaders expect.
        let mtlVD = MTLVertexDescriptor()
        // Position attribute at index 0, float3, offset=0
        mtlVD.attributes[VertexAttribute.position.rawValue].format = .float3
        mtlVD.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVD.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue

        // Texcoord attribute at index 1, float2, offset=0
        mtlVD.attributes[VertexAttribute.texcoord.rawValue].format = .float2
        mtlVD.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVD.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue

        // Layout for bufferIndex 0 (positions): stride = 3×4 = 12 bytes per vertex
        mtlVD.layouts[BufferIndex.meshPositions.rawValue].stride = MemoryLayout<Float>.stride * 3
        mtlVD.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVD.layouts[BufferIndex.meshPositions.rawValue].stepFunction = .perVertex

        // Layout for bufferIndex 1 (texcoords): stride = 2×4 = 8 bytes per vertex
        mtlVD.layouts[BufferIndex.meshGenerics.rawValue].stride = MemoryLayout<Float>.stride * 2
        mtlVD.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVD.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = .perVertex

        // Save the descriptor so callers can pass it into their pipeline‐creation code
        self.mtlVertexDescriptor = mtlVD

        // 2) Convert that MTLVertexDescriptor into a ModelIO descriptor so MDLMesh knows how to fill buffers.
        let mdlVD = MTKModelIOVertexDescriptorFromMetal(mtlVD)
        guard let attributes = mdlVD.attributes as? [MDLVertexAttribute] else {
            throw RendererError.badVertexDescriptor
        }

        // Name the ModelIO attributes so MDLMesh knows “this is position” and “this is texcoord”
        attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
        attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate

        // 3) Create the MDLMesh for a box of given size & segments
        let allocator = MTKMeshBufferAllocator(device: device)
        let dimensions = SIMD3<Float>(scale, scale, scale)
        let mdlMesh = MDLMesh.newBox(
            withDimensions: dimensions,
            segments: segments,
            geometryType: .triangles,
            inwardNormals: false,
            allocator: allocator
        )

        mdlMesh.vertexDescriptor = mdlVD

        // 4) Create the MTKMesh from the MDLMesh
        self.mesh = try MTKMesh(mesh: mdlMesh, device: device)
    }
}
