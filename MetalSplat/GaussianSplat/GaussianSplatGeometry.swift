import Metal
import simd

enum GaussianSplatError: Error {
    case bufferAllocationFailed
}

class GaussianSplatGeometry: SplatGeometry {

    public let splatCount:    Int
    public let paddedCount:   Int   // next power-of-2 ≥ splatCount
    public let splatBuffer:   MTLBuffer
    public let sortedIndexBuffer: MTLBuffer
    public let keysBuffer:    MTLBuffer  // Float per padded slot

    let sorter: GPUSorter

    init(device: MTLDevice, splats: [GaussianSplatData]) throws {
        self.splatCount  = splats.count
        self.paddedCount = GaussianSplatGeometry.nextPow2(splats.count)
        self.sorter      = try GPUSorter(device: device)

        guard let sb = device.makeBuffer(
            bytes: splats,
            length: splats.count * MemoryLayout<GaussianSplatData>.stride,
            options: .storageModeShared) else { throw GaussianSplatError.bufferAllocationFailed }
        splatBuffer = sb
        splatBuffer.label = "SplatBuffer"

        // sortedIndexBuffer and keysBuffer are GPU-private — written by compute, read by vertex shader
        guard let ib = device.makeBuffer(
            length: paddedCount * MemoryLayout<UInt32>.stride,
            options: .storageModePrivate) else { throw GaussianSplatError.bufferAllocationFailed }
        sortedIndexBuffer = ib
        sortedIndexBuffer.label = "SplatSortedIndices"

        guard let kb = device.makeBuffer(
            length: paddedCount * MemoryLayout<Float>.stride,
            options: .storageModePrivate) else { throw GaussianSplatError.bufferAllocationFailed }
        keysBuffer = kb
        keysBuffer.label = "SplatDepthKeys"
        // Both buffers are initialized by computeDepthKeys on the first sort pass.
    }

    // MARK: - SplatGeometry

    func sortSplats(commandBuffer: MTLCommandBuffer, cameraPosition: SIMD3<Float>, cameraForward: SIMD3<Float>) {
        sorter.encode(
            commandBuffer:  commandBuffer,
            splatBuffer:    splatBuffer,
            keysBuffer:     keysBuffer,
            indexBuffer:    sortedIndexBuffer,
            splatCount:     splatCount,
            paddedCount:    paddedCount,
            cameraPosition: cameraPosition,
            cameraForward:  cameraForward)
    }

    // MARK: - Geometry

    func draw(encoder: MTLRenderCommandEncoder, context: RenderContext) {
        // sort is encoded before this render pass by the renderer
        encoder.pushDebugGroup("Draw Splats")
        encoder.setCullMode(.none)
        encoder.setRenderPipelineState(context.renderState.pipelineState)
        encoder.setDepthStencilState(context.renderState.depthStencilState)

        var su = SplatUniforms(projectionMatrix: context.projectionMatrix,
                               viewMatrix: context.viewMatrix,
                               modelMatrix: context.nodeWorldTM,
                               viewportSize: context.viewportSize,
                               _pad: .zero)
        encoder.setVertexBytes(&su, length: MemoryLayout<SplatUniforms>.size,
                               index: Int(BufferIndex.splatUniforms.rawValue))

        encodeDraw(encoder: encoder)
        encoder.popDebugGroup()
    }

    func encodeDraw(encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(splatBuffer,       offset: 0, index: Int(BufferIndex.splats.rawValue))
        encoder.setVertexBuffer(sortedIndexBuffer, offset: 0, index: Int(BufferIndex.splatIndices.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: splatCount * 6)
    }

    // MARK: - Helpers

    private static func nextPow2(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
