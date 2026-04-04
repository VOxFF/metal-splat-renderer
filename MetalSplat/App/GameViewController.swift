//
//  GameViewController.swift
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/5/25.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer

        addLoadButton()
    }

    // MARK: - Load Splat button

    private func addLoadButton() {
        let button = NSButton(title: "Load Splat…", target: self, action: #selector(loadSplatFile(_:)))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
    }

    private var openPanel: NSOpenPanel?

    @objc func loadSplatFile(_ sender: Any?) {
        if let panel = openPanel {
            panel.makeKeyAndOrderFront(nil)  // bring existing panel to front
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Open Gaussian Splat"
        panel.allowedFileTypes = ["ply"]
        panel.allowsMultipleSelection = false
        openPanel = panel
        panel.begin { [weak self] response in
            self?.openPanel = nil
            guard response == .OK, let url = panel.url else { return }
            self?.renderer.loadSplats(from: url)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(self)
    }

    // MARK: - Orbit (left drag)

    override func mouseDragged(with event: NSEvent) {
        renderer.camera.orbit(dx: Float(event.deltaX), dy: Float(event.deltaY))
    }

    // MARK: - Pan (middle drag)

    override func otherMouseDragged(with event: NSEvent) {
        renderer.camera.pan(dx: Float(event.deltaX), dy: Float(event.deltaY))
    }

    // MARK: - Dolly (scroll wheel / trackpad)

    override func scrollWheel(with event: NSEvent) {
        renderer.camera.dolly(delta: Float(event.scrollingDeltaY))
    }
}
