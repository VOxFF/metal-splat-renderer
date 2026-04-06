import Foundation

class DefaultMaterial : Material {
    public let vertex_shader: String = "vertexShader"
    public let fragment_shader: String = "fragmentShader"
    
    public var textureKeys: [TextureIndex: TextureKey] = [:]
    
}
