import Foundation
import Metal

protocol Texture : AnyObject {
    var texture: MTLTexture { get }
}

