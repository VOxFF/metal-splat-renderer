import Metal
import simd

/// All per-node render state the renderer passes down to geometry draw calls.
/// Geometry types pull only what they need from this context.
struct RenderContext {
    let renderState:      RenderState
    let projectionMatrix: matrix_float4x4
    let viewMatrix:       matrix_float4x4
    let cameraPosition:   SIMD3<Float>
    let nodeWorldTM:      matrix_float4x4
    let viewportSize:     SIMD2<Float>
    let textures:         [TextureIndex: MTLTexture]  // resolved for this node's material
}
