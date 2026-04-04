import Foundation

class GaussianSplatMaterial: Material {
    let vertex_shader:   String = "splatVertexShader"
    let fragment_shader: String = "splatFragmentShader"
    var textureKeys: [TextureIndex: TextureKey] = [:]  // splats don't use textures
}
