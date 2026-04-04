import Metal
import simd

/// Encodes a full GPU bitonic sort of splats (back-to-front) into a compute encoder.
final class GPUSorter {

    private let depthKeysPipeline:  MTLComputePipelineState
    private let bitonicStepPipeline: MTLComputePipelineState

    init(device: MTLDevice) throws {
        let lib = device.makeDefaultLibrary()!
        depthKeysPipeline   = try device.makeComputePipelineState(
            function: lib.makeFunction(name: "computeDepthKeys")!)
        bitonicStepPipeline = try device.makeComputePipelineState(
            function: lib.makeFunction(name: "bitonicSortStep")!)
    }

    func encode(
        commandBuffer:  MTLCommandBuffer,
        splatBuffer:    MTLBuffer,
        keysBuffer:     MTLBuffer,
        indexBuffer:    MTLBuffer,
        splatCount:     Int,
        paddedCount:    Int,
        cameraPosition: SIMD3<Float>,
        cameraForward:  SIMD3<Float>
    ) {
        guard let enc = commandBuffer.makeComputeCommandEncoder() else { return }
        enc.label = "GPUSorter"

        // --- Pass 1: reset indices to identity + compute view-depth keys ---
        // Must run every frame: bitonic sort scrambles both buffers,
        // so the (key, index) identity mapping must be rebuilt before each sort.
        enc.setComputePipelineState(depthKeysPipeline)
        enc.setBuffer(splatBuffer, offset: 0, index: 0)
        enc.setBuffer(keysBuffer,  offset: 0, index: 1)
        enc.setBuffer(indexBuffer, offset: 0, index: 2)
        var cam     = cameraPosition
        var fwd     = cameraForward
        var sc      = UInt32(splatCount)
        var pc      = UInt32(paddedCount)
        enc.setBytes(&cam, length: MemoryLayout<SIMD3<Float>>.size, index: 3)
        enc.setBytes(&fwd, length: MemoryLayout<SIMD3<Float>>.size, index: 4)
        enc.setBytes(&sc,  length: MemoryLayout<UInt32>.size,       index: 5)
        enc.setBytes(&pc,  length: MemoryLayout<UInt32>.size,       index: 6)

        let tpg1  = min(depthKeysPipeline.maxTotalThreadsPerThreadgroup, paddedCount)
        enc.dispatchThreads(
            MTLSize(width: paddedCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tpg1, height: 1, depth: 1))

        // --- Pass 2: bitonic sort ---
        enc.setComputePipelineState(bitonicStepPipeline)
        enc.setBuffer(keysBuffer,  offset: 0, index: 0)
        enc.setBuffer(indexBuffer, offset: 0, index: 1)

        // One thread per element: the XOR pattern requires all paddedCount threads
        // so that pairs in the upper half of the array are also compared.
        // The (ixj <= i) guard in the kernel ensures each pair runs exactly once.
        let tpg2 = min(bitonicStepPipeline.maxTotalThreadsPerThreadgroup, paddedCount)

        var k = 2
        while k <= paddedCount {
            var j = k / 2
            while j >= 1 {
                // SortParams: { uint k, uint j, uint n=paddedCount }
                var params = (UInt32(k), UInt32(j), UInt32(paddedCount))
                enc.setBytes(&params, length: MemoryLayout<(UInt32, UInt32, UInt32)>.size, index: 2)
                enc.memoryBarrier(scope: .buffers)
                enc.dispatchThreads(
                    MTLSize(width: paddedCount, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: tpg2, height: 1, depth: 1))
                j /= 2
            }
            k *= 2
        }

        enc.endEncoding()
    }
}
