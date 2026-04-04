//
//  Texture.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/26/25.
//

import Foundation
import Metal

protocol Texture : AnyObject {
    var texture: MTLTexture { get }
}

