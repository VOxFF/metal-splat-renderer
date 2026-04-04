//
//  Node.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/10/25.
//

import Foundation
import simd

class Node {
    public var name: String = "Node"
    
    public var geometry: Geometry?
    public var material: Material?
    public var transform: Transform = Transform()
    
    public var tm: matrix_float4x4 = matrix_identity_float4x4
    public var tmFn: ((Transform) -> matrix_float4x4)?  /// “custom lambda”
    
    public var children: [Node] = []  /// child nodes
    public weak var parent: Node?
   
    init(
         geometry: Geometry? = nil,
         materaial: Material? = nil,
         tmFn: ((Transform) -> matrix_float4x4)? = nil,
         tm: matrix_float4x4 = matrix_identity_float4x4)
    {
        self.tm = tm
        self.geometry = geometry
        self.material = materaial
        self.tmFn = tmFn
    }
    
    func addChild(_ child: Node)
    {
        children.append(child)
        child.parent = self
    }
    
    func worldTM() -> matrix_float4x4
    {
        guard let parent = parent else { return tm }
        return parent.worldTM() * tm
    }

    func update() {
        tm = tmFn?(transform) ?? transform.matrix()
    }
}
