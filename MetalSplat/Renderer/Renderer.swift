//
//  Renderer.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/5/25.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 10

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {

    public let view: MTKView
    public let device: MTLDevice
    
    var root: Node!
    var renderStateCache: [RenderStateKey: RenderState] = [:]
    var textureCache: [TextureKey: Texture] = [:]
    
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    var uniformBufferOffset = 0
    var uniformBufferIndex = 0

    var uniforms: UnsafeMutablePointer<Uniforms>

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    let camera = Camera()

    
    
    @MainActor
    init?(metalKitView: MTKView) {
        
        self.view = metalKitView
        self.device = metalKitView.device!
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        

        self.commandQueue = self.device.makeCommandQueue()!

        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        self.dynamicUniformBuffer = self.device.makeBuffer(length:uniformBufferSize,
                                                           options:[MTLResourceOptions.storageModeShared])!
        self.dynamicUniformBuffer.label = "UniformBuffer"
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)


        super.init()
        self.loadScene()
        self.cacheRenderStates()
        self.cacheTextures()

    }
    
    func traverse(from root: Node, nodeFn: (Node) -> Void) {
        var queue: [Node] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            nodeFn(current)

            queue.append(contentsOf: current.children)
        }
    }
    
    func loadScene() {
        do {
            self.root = Node()
            self.root.name = "Root"

            let mtl = DefaultMaterial()
            mtl.setTexture(filename: "ColorMap", at: TextureIndex.color)

            let box1 = try Box(device: device, scale: 2.0, segments: SIMD3<UInt32>(2,2,2))
            let node1 = Node(geometry: box1, materaial: mtl, tmFn: { t in
                t.position = SIMD3<Float>(-4, 0, 0)
                let dq = simd_quatf(angle: 0.01, axis: normalize(SIMD3<Float>(1, 1, 0)))
                t.rotation = dq * t.rotation
                return t.matrix()
            })
            node1.name = "Box1"

            let box2 = try Box(device: device, scale: 2.0, segments: SIMD3<UInt32>(2,2,2))
            let node2 = Node(geometry: box2, materaial: mtl, tmFn: { t in
                t.position = SIMD3<Float>(4, 0, 0)
                let dq = simd_quatf(angle: -0.015, axis: normalize(SIMD3<Float>(0, 1, 1)))
                t.rotation = dq * t.rotation
                return t.matrix()
            })
            node2.name = "Box2"

            root.addChild(node1)
            root.addChild(node2)

        } catch {
            print("Box creation failed: \(error)")
            return
        }
    }
    
    func updateScene() {
        traverse(from: self.root) { $0.update() }
    }
    
    func cacheRenderStates() {
        traverse(from: self.root) { node in
            guard let material = node.material,
                  let geometry = node.geometry else { return }

            let key = RenderStateKey(material: material, vertexDescriptor: geometry.mtlVertexDescriptor)
            if renderStateCache[key] == nil {
                do {
                    renderStateCache[key] = try RenderState(device: device, mtkView: view,
                                                            material: material, geometry: geometry)
                } catch {
                    print("Failed to create RenderState for node: \(error)")
                }
            }
        }
        print("RenderState cache size: \(renderStateCache.count)")
    }
    
    func cacheTextures(){
        traverse(from: self.root) { node in
            guard let material = node.material else { return }

            for (slot, key) in material.textureKeys {
                guard textureCache[key] == nil else { continue }
                switch key {
                case let .file(name, usage, storage):
                    do {
                        let tex = try FileTexture(device: device, name: name, usage: usage, storage: storage)
                        textureCache[key] = tex
                    } catch {
                        print("Failed to load texture: \(error)")
                    }
                    
                case let .fbo(width, height, pixelFormat, usage, storage):
                    print("Add later")
                    // load an FBOTexture (or wrap it in your Texture protocol)
                    
                }
            }   //end for
        } // end of lambda
        print("Texture cache size: \(textureCache.count)")
    }

    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering

        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex

        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
    }
    
    func draw(node: Node, encoder: MTLRenderCommandEncoder) {  /// Call for every node in hierarchy
        
        guard let material = node.material,
              let geometry = node.geometry else { return }
        
        let key = RenderStateKey(material: material, vertexDescriptor: geometry.mtlVertexDescriptor)
        guard let state = renderStateCache[key] else {
            print("RenderState not found.")
            return
        }
        
        encoder.pushDebugGroup("Draw Box")
        
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setRenderPipelineState(state.pipelineState)
        encoder.setDepthStencilState(state.depthStencilState)
        
        
        /// set uniforms — pass inline so each node gets its own transform
        var nodeUniforms = Uniforms(projectionMatrix: projectionMatrix,
                                   modelViewMatrix: simd_mul(camera.viewMatrix, node.worldTM()))
        encoder.setVertexBytes(&nodeUniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentBytes(&nodeUniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
        
        let mesh = geometry.mesh
        for (index, element) in mesh.vertexDescriptor.layouts.enumerated()
        {
            guard let layout = element as? MDLVertexBufferLayout else { return }
            if layout.stride != 0 {
                let buffer = mesh.vertexBuffers[index]
                encoder.setVertexBuffer(buffer.buffer, offset:buffer.offset, index: index)
            }
        }
        for (slot, key) in material.textureKeys {
            guard let tex = textureCache[key] else { continue }
            encoder.setFragmentTexture(tex.texture, index: slot.rawValue)
        }
        //encoder.setFragmentTexture(colorMap, index: TextureIndex.color.rawValue)
        
        for submesh in mesh.submeshes {
            encoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
            
        }
        encoder.popDebugGroup()
        
    }

    func draw(in view: MTKView) { /// Per frame updates here
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in semaphore.signal() }
            
            self.updateDynamicBufferState()
            self.updateScene()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            if let renderPassDescriptor = view.currentRenderPassDescriptor {
                
                /// Final pass rendering code here
                if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    renderEncoder.label = "Primary Render Encoder"
                    //renderEncoder.pushDebugGroup("Draw Box")
                    
                    traverse(from: root) { draw(node: $0, encoder: renderEncoder) }
                    
                    //renderEncoder.popDebugGroup()
                    renderEncoder.endEncoding()
                    
                    if let drawable = view.currentDrawable {
                        commandBuffer.present(drawable)
                    }
                }
            }
            commandBuffer.commit()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}

