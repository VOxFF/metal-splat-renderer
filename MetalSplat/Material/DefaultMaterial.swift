//
//  DefaultMaterial.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/11/25.
//

import Foundation

class DefaultMaterial : Material {
    public let vertex_shader: String = "vertexShader"
    public let fragment_shader: String = "fragmentShader"
    
    public var textureKeys: [TextureIndex: TextureKey] = [:]
    
}
