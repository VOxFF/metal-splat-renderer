//
//  Geometry.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/10/25.
//

import MetalKit

protocol Geometry : AnyObject {
  var mesh: MTKMesh { get }
  var mtlVertexDescriptor: MTLVertexDescriptor { get }
}
