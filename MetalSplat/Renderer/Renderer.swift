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
    let inFlightSemaphore = DispatchSemaphore(value: 3)

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
        self.root = Node()
        self.root.name = "Root"

        do {
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

            // root.addChild(node1)
            // root.addChild(node2)
        } catch {
            print("Box creation failed: \(error)")
        }

        do {
            let splats = ProceduralSplats.grid(count: 5, spacing: 0.6, scale: 0.15)
            print("Procedural splat count: \(splats.count)")
            let splatGeometry = try GaussianSplatGeometry(device: device, splats: splats)
            let splatNode = Node(geometry: splatGeometry, materaial: GaussianSplatMaterial())
            splatNode.name = "TestSplats"
            root.addChild(splatNode)
            print("Splat node added to scene")
        } catch {
            print("Splat creation failed: \(error)")
        }
    }
    
    func updateScene() {
        traverse(from: self.root) { $0.update() }
    }
    
    func cacheRenderStates() {
        traverse(from: self.root) { node in
            guard let material = node.material, let geometry = node.geometry else { return }
            print("Caching render state for '\(node.name)' type=\(type(of: geometry))")
            let key = RenderStateKey(material: material, vertexDescriptor: geometry.vertexDescriptor)
            guard renderStateCache[key] == nil else {
                print("  → already cached")
                return
            }
            do {
                renderStateCache[key] = try geometry.makeRenderState(device: device, mtkView: view, material: material)
                print("  → created OK")
            } catch {
                print("  → FAILED: \(error)")
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

    func draw(node: Node, encoder: MTLRenderCommandEncoder) {
        guard let material = node.material,
              let geometry = node.geometry else { return }

        let key = RenderStateKey(material: material, vertexDescriptor: geometry.vertexDescriptor)
        guard let state = renderStateCache[key] else {
            print("No render state for '\(node.name)' — key missing from cache")
            return
        }

        let ctx = RenderContext(
            renderState:      state,
            projectionMatrix: projectionMatrix,
            viewMatrix:       camera.viewMatrix,
            cameraPosition:   camera.position,
            nodeWorldTM:      node.worldTM(),
            viewportSize:     SIMD2<Float>(Float(view.drawableSize.width),
                                           Float(view.drawableSize.height)),
            textures:         resolvedTextures(for: material))

        geometry.draw(encoder: encoder, context: ctx)
    }

    private func resolvedTextures(for material: Material) -> [TextureIndex: MTLTexture] {
        var result: [TextureIndex: MTLTexture] = [:]
        for (slot, key) in material.textureKeys {
            result[slot] = textureCache[key]?.texture
        }
        return result
    }

    func draw(in view: MTKView) {

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer) in semaphore.signal() }

            self.updateScene()

            if let renderPassDescriptor = view.currentRenderPassDescriptor,
               let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {

                renderEncoder.label = "Primary Render Encoder"

                // Collect nodes by render phase in one traversal
                var opaqueNodes: [Node] = []
                var transparentNodes: [Node] = []
                traverse(from: root) { node in
                    guard node.geometry != nil else { return }
                    if node.geometry is SplatGeometry { transparentNodes.append(node) }
                    else { opaqueNodes.append(node) }
                }

                // Opaque first (writes depth), transparent second (reads depth, no depth write)
                opaqueNodes.forEach      { draw(node: $0, encoder: renderEncoder) }
                transparentNodes.forEach { draw(node: $0, encoder: renderEncoder) }

                renderEncoder.endEncoding()

                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            commandBuffer.commit()
        }
    }

    // MARK: - Scene mutations

    /// Replace all splat nodes with geometry loaded from a PLY file.
    /// File I/O runs on a background thread; scene update on main.
    func loadSplats(from url: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let splats = try SplatPLYLoader.load(url: url)
                print("Loaded \(splats.count) splats from \(url.lastPathComponent)")
                let geometry = try GaussianSplatGeometry(device: self.device, splats: splats)
                DispatchQueue.main.async {
                    self.root.children.removeAll { $0.geometry is SplatGeometry }
                    let node = Node(geometry: geometry, materaial: GaussianSplatMaterial())
                    node.name = url.deletingPathExtension().lastPathComponent
                    self.root.addChild(node)
                    self.cacheRenderStates()
                }
            } catch {
                print("Failed to load splats: \(error)")
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}

