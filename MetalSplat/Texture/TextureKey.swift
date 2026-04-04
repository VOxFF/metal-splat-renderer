//
//  TextureKey.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/26/25.
//

import Foundation
import Metal


import Metal

enum TextureKey {
    case file(name: String,
              usage: MTLTextureUsage = .shaderRead,
              storage: MTLStorageMode = .private)
    case fbo(width: Int,
             height: Int,
             pixelFormat: MTLPixelFormat,
             usage: MTLTextureUsage = .renderTarget,
             storage: MTLStorageMode = .private)
}

extension TextureKey: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .file(name, usage, storage):
            hasher.combine(0)                   // discriminator for `file`
            hasher.combine(name)
            hasher.combine(usage.rawValue)
            hasher.combine(storage.rawValue)
        case let .fbo(width, height, pixelFormat, usage, storage):
            hasher.combine(1)                   // discriminator for `fbo`
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(pixelFormat.rawValue)
            hasher.combine(usage.rawValue)
            hasher.combine(storage.rawValue)
        }
    }

    static func ==(lhs: TextureKey, rhs: TextureKey) -> Bool {
        switch (lhs, rhs) {
        case let (.file(n1, u1, s1), .file(n2, u2, s2)):
            return n1 == n2 && u1 == u2 && s1 == s2
        case let (.fbo(w1, h1, pf1, u1, s1), .fbo(w2, h2, pf2, u2, s2)):
            return w1 == w2
                && h1 == h2
                && pf1 == pf2
                && u1 == u2
                && s1 == s2
        default:
            return false
        }
    }
}


