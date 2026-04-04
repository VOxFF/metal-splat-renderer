import Metal
import MetalKit


/// Internal key type for hashing & equality
private struct FileTextureParams: Hashable {
    let name: String
    let usageRaw: UInt
    let storageRaw: UInt
}

/// A bundle‐loaded texture that conforms to `Texture` and `Hashable`
class FileTexture: Texture, Hashable {
    // The underlying Metal texture
    public let texture: MTLTexture

    // All the parameters that uniquely identify this texture
    private let params: FileTextureParams

    /// Designated initializer: throws if load fails
    init(device: MTLDevice,
         name: String,
         usage: MTLTextureUsage = .shaderRead,
         storage: MTLStorageMode = .private) throws
    {
        // Capture our key params
        self.params = FileTextureParams(
            name: name,
            usageRaw: usage.rawValue,
            storageRaw: storage.rawValue
        )

        // Load the MTLTexture
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage:       NSNumber(value: usage.rawValue),
            .textureStorageMode: NSNumber(value: storage.rawValue)
        ]
        self.texture = try loader.newTexture(
            name: name,
            scaleFactor: 1.0,
            bundle: nil,
            options: options
        )
    }

    // MARK: – Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(params)
    }

    static func == (lhs: FileTexture, rhs: FileTexture) -> Bool {
        return lhs.params == rhs.params
    }
}
