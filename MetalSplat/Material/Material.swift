//
//  Material.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/11/25.
//

import Foundation
import Metal

enum TextureIndex: Int {
  case color    = 0
  case normal   = 1
  case roughness = 2
  // … etc …
}

protocol Material : AnyObject {
    var vertex_shader: String { get }
    var fragment_shader: String { get }
    
    var textureKeys: [TextureIndex: TextureKey] { get set }
    
}


extension Material {
    /// Point this material at a new file for the given slot
    func setTexture(filename: String,
                    usage: MTLTextureUsage = .shaderRead,
                    storage: MTLStorageMode = .private,
                    at index: TextureIndex)
    {
        // overwrite whatever was there with a new file-key
        textureKeys[index] = .file(
            name: filename,
            usage: usage,
            storage: storage
        )
    }
}

extension Material {
    func hashValue() -> Int {
        var hasher = Hasher()
        hasher.combine(vertex_shader)
        hasher.combine(fragment_shader)
        return hasher.finalize()
    }
}
