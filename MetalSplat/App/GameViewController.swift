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
        addZoomSpeedSlider()
    }

    // MARK: - Zoom speed slider

    private func addZoomSpeedSlider() {
        let zoomLabel = NSTextField(labelWithString: "Zoom speed")
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false

        let zoomSlider = NSSlider(value: 0.2, minValue: 0.05, maxValue: 1.0, target: self, action: #selector(zoomSpeedChanged(_:)))
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        zoomSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let minLabel = NSTextField(labelWithString: "Min distance")
        minLabel.translatesAutoresizingMaskIntoConstraints = false

        let minSlider = NSSlider(value: 0.4, minValue: 0.05, maxValue: 5.0, target: self, action: #selector(minRadiusChanged(_:)))
        minSlider.translatesAutoresizingMaskIntoConstraints = false
        minSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let stack = NSStackView(views: [zoomLabel, zoomSlider, minLabel, minSlider])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12)
        ])
    }

    @objc private func zoomSpeedChanged(_ sender: NSSlider) {
        renderer.camera.zoomSpeed = Float(sender.doubleValue)
    }

    @objc private func minRadiusChanged(_ sender: NSSlider) {
        renderer.camera.minRadius = Float(sender.doubleValue)
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

    // MARK: - Orbit (left drag) / Pan (Cmd + left drag or middle drag)

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            renderer.camera.pan(dx: Float(event.deltaX), dy: Float(event.deltaY))
        } else {
            renderer.camera.orbit(dx: Float(event.deltaX), dy: Float(event.deltaY))
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        renderer.camera.pan(dx: Float(event.deltaX), dy: Float(event.deltaY))
    }

    // MARK: - Dolly (scroll wheel / trackpad)

    override func scrollWheel(with event: NSEvent) {
        renderer.camera.dolly(delta: Float(event.scrollingDeltaY))
    }
}
