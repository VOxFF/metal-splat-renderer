import Foundation
import Metal
import MetalKit

extension MTLVertexDescriptor {
    func hashValue() -> Int {
        var hasher = Hasher()

        // Hash all active vertex attributes
        let maxAttrIndex = (0..<31).last(where: { attributes[$0] != nil }) ?? -1
        for i in 0...maxAttrIndex {
            if let attr = attributes[i] {
                hasher.combine(i)
                hasher.combine(attr.bufferIndex)
                hasher.combine(attr.format.rawValue)
                hasher.combine(attr.offset)
            }
        }

        // Hash all active buffer layouts
        let maxLayoutIndex = (0..<31).last(where: { layouts[$0] != nil }) ?? -1
        for i in 0...maxLayoutIndex {
            if let layout = layouts[i] {
                hasher.combine(i)
                hasher.combine(layout.stride)
                hasher.combine(layout.stepFunction.rawValue)
                hasher.combine(layout.stepRate)
            }
        }

        return hasher.finalize()
    }
}
