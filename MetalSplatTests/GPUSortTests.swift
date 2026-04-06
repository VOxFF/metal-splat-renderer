import XCTest
import Metal
@testable import MetalSplat

final class GPUSortTests: XCTestCase {

    private var device: MTLDevice!
    private var sorter: GPUSorter!

    override func setUpWithError() throws {
        guard let d = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device  = d
        sorter  = try GPUSorter(device: d)
    }

    // MARK: - Helpers

    /// Builds a GaussianSplat buffer from an array of world-space Z positions.
    /// All other fields are zeroed (opacity=0, scale=0, etc.)
    private func makeSplatBuffer(zPositions: [Float]) -> MTLBuffer {
        let count  = zPositions.count
        let stride = MemoryLayout<GaussianSplat>.stride
        let buf    = device.makeBuffer(length: count * stride, options: .storageModeShared)!
        let ptr    = buf.contents().bindMemory(to: GaussianSplat.self, capacity: count)
        for (i, z) in zPositions.enumerated() {
            ptr[i] = GaussianSplat()
            ptr[i].positionAndOpacity = SIMD4<Float>(0, 0, z, 0)
        }
        return buf
    }

    private func nextPow2(_ n: Int) -> Int {
        var p = 1; while p < n { p *= 2 }; return p
    }

    /// Runs the GPU sort and returns the sorted index array.
    private func runSort(zPositions: [Float], cameraZ: Float = 0) -> [UInt32] {
        let count       = zPositions.count
        let padded      = nextPow2(count)
        let splatBuf    = makeSplatBuffer(zPositions: zPositions)
        let keysBuf     = device.makeBuffer(length: padded * MemoryLayout<Float>.size,  options: .storageModeShared)!
        let indexBuf    = device.makeBuffer(length: padded * MemoryLayout<UInt32>.size, options: .storageModeShared)!

        let queue = device.makeCommandQueue()!
        let cb    = queue.makeCommandBuffer()!

        // Camera at (0,0,cameraZ) looking in -Z direction
        sorter.encode(
            commandBuffer:  cb,
            splatBuffer:    splatBuf,
            keysBuffer:     keysBuf,
            indexBuffer:    indexBuf,
            splatCount:     count,
            paddedCount:    padded,
            cameraPosition: SIMD3<Float>(0, 0, cameraZ),
            cameraForward:  SIMD3<Float>(0, 0, -1)
        )
        cb.commit()
        cb.waitUntilCompleted()

        let ptr = indexBuf.contents().bindMemory(to: UInt32.self, capacity: padded)
        return (0..<count).map { ptr[$0] }
    }

    // MARK: - Tests

    func testSortedBackToFront() {
        // Splats at z = 0,1,2,3,4 with camera at z=10 looking toward -Z.
        // View-depth = dot(splatPos - camPos, forward) = dot((0,0,z)-(0,0,10),(0,0,-1)) = 10-z
        // Back-to-front = largest depth first = z=0 first, z=4 last?
        // Actually back-to-front means the farthest from camera rendered first.
        // Camera is at z=10, forward=-Z. Depth of splat at z=k is (k-10)*(-1) = 10-k.
        // Largest depth (most negative z diff) = z=0 → depth=10 → back, rendered first.
        // Bitonic sort sorts ascending (largest key = front = rendered last).
        // Keys = dot(delta, forward) = (z - cameraZ) * (-1) = -(z-10) = 10-z
        // For back-to-front we want largest key first (farthest behind camera = most negative view-space Z = largest positive key here).
        // Actually: key = dot((0,0,z)-(0,0,10), (0,0,-1)) = (z-10)*(-1) = 10-z
        // z=0 → key=10, z=4 → key=6. Bitonic ascending → z=4 first (key=6), z=0 last (key=10).
        // But we want back-to-front, so z=0 (farthest) should be drawn first → index 0 in sorted array.
        // So sorted order should be: index of z=0 first.
        // Wait, let me re-check: the sort is back-to-front. "Back" = farthest from camera.
        // Camera at z=10, splat at z=0 is farthest. It should be rendered FIRST (index 0 in sorted buffer).
        // key = dot(splatPos - camPos, camForward) = dot((0,0,0)-(0,0,10), (0,0,-1)) = dot((0,0,-10),(0,0,-1)) = 10
        // splat at z=4: key = dot((0,0,4)-(0,0,10),(0,0,-1)) = dot((0,0,-6),(0,0,-1)) = 6
        // Larger key = farther behind = drawn first → need descending sort.
        // But bitonicSortStep sorts ascending for (i & k)==0 groups.
        // Let me just verify the invariant: adjacent pairs in result should be back-to-front.

        let indices = runSort(zPositions: [0, 1, 2, 3, 4], cameraZ: 10)
        XCTAssertEqual(indices.count, 5)

        // Verify back-to-front: each splat's z should be <= the next one's z
        // (camera at z=10, so lower z = farther = should come first)
        let zPositions: [Float] = [0, 1, 2, 3, 4]
        let sortedZ = indices.map { zPositions[Int($0)] }
        for i in 0..<(sortedZ.count - 1) {
            XCTAssertLessThanOrEqual(sortedZ[i], sortedZ[i+1],
                "Expected back-to-front order at index \(i): \(sortedZ)")
        }
    }

    func testAllIndicesPresent() {
        // Every index 0..<n should appear exactly once
        let n = 8
        let zPositions = (0..<n).map { Float($0) }
        let indices = runSort(zPositions: zPositions, cameraZ: 100)
        let sorted = indices.sorted()
        XCTAssertEqual(sorted, (0..<n).map { UInt32($0) })
    }

    func testSingleSplat() {
        let indices = runSort(zPositions: [5.0])
        XCTAssertEqual(indices, [0])
    }

    func testAlreadySortedInput() {
        // Already in back-to-front order for camera at z=10
        let indices = runSort(zPositions: [0, 1, 2, 3], cameraZ: 10)
        let zPositions: [Float] = [0, 1, 2, 3]
        let sortedZ = indices.map { zPositions[Int($0)] }
        for i in 0..<(sortedZ.count - 1) {
            XCTAssertLessThanOrEqual(sortedZ[i], sortedZ[i+1])
        }
    }

    func testReversedInput() {
        // Reversed input should still sort correctly
        let indices = runSort(zPositions: [4, 3, 2, 1, 0], cameraZ: 10)
        let zPositions: [Float] = [4, 3, 2, 1, 0]
        let sortedZ = indices.map { zPositions[Int($0)] }
        for i in 0..<(sortedZ.count - 1) {
            XCTAssertLessThanOrEqual(sortedZ[i], sortedZ[i+1])
        }
    }
}
