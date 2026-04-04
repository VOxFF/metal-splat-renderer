import Metal
import simd

class GaussianSplatGeometry: SplatGeometry {

    public let splatCount: Int
    public let splatBuffer: MTLBuffer
    public let sortedIndexBuffer: MTLBuffer

    private let splats: [GaussianSplatData]  // CPU mirror for sort key computation

    init(device: MTLDevice, splats: [GaussianSplatData]) {
        self.splatCount = splats.count
        self.splats = splats

        // storageModeShared — CPU writes sorted indices, GPU reads splat data
        splatBuffer = device.makeBuffer(
            bytes: splats,
            length: splats.count * MemoryLayout<GaussianSplatData>.stride,
            options: .storageModeShared)!
        splatBuffer.label = "SplatBuffer"

        sortedIndexBuffer = device.makeBuffer(
            length: splats.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared)!
        sortedIndexBuffer.label = "SplatSortedIndices"

        // Identity order — overwritten every frame by sortSplats()
        let ptr = sortedIndexBuffer.contents().bindMemory(to: UInt32.self, capacity: splats.count)
        for i in 0..<splats.count { ptr[i] = UInt32(i) }
    }

    // MARK: - SplatGeometry

    func sortSplats(cameraPosition: SIMD3<Float>) {
        // Compute squared distance from each splat to the camera.
        // Sorting by squared distance is equivalent to sorting by distance
        // and avoids a sqrt per splat.
        let sorted = splats.indices.sorted {
            let a = SIMD3<Float>(splats[$0].posX, splats[$0].posY, splats[$0].posZ) - cameraPosition
            let b = SIMD3<Float>(splats[$1].posX, splats[$1].posY, splats[$1].posZ) - cameraPosition
            return dot(a, a) > dot(b, b)  // back-to-front: farthest first
        }

        let ptr = sortedIndexBuffer.contents().bindMemory(to: UInt32.self, capacity: splatCount)
        for (i, idx) in sorted.enumerated() {
            ptr[i] = UInt32(idx)
        }
    }

    // MARK: - Geometry

    func encodeDraw(encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(splatBuffer,       offset: 0, index: Int(BufferIndex.splats.rawValue))
        encoder.setVertexBuffer(sortedIndexBuffer, offset: 0, index: Int(BufferIndex.splatIndices.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: splatCount * 6)
    }
}
