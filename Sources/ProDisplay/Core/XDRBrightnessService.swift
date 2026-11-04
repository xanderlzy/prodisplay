import AppKit
import CoreGraphics
import Metal
import QuartzCore

/// Extended brightness for XDR panels.
///
/// A 1×1 pt window shows an HDR pixel so macOS switches the panel into EDR mode
/// (raising the backlight). The display's gamma table is then scaled above 1.0,
/// which brightens all SDR content into the HDR headroom. Gamma changes reset
/// automatically when the process exits.
///
/// This service applies values immediately; `BrightnessController` animates them.
@MainActor
final class XDRBrightnessService {
    /// Called when the boost is switched off for safety (heat or low battery).
    var onSafetyStop: (() -> Void)?

    private(set) var isActive = false
    private var display: CGDirectDisplayID = 0
    /// The boost factor asked for, and the one applied (capped by the headroom macOS has granted so far).
    private var requested = 1.0
    private var applied = 1.0
    /// The display's colour table before boosting; the boost scales it.
    private var baseTable: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])?

    private var triggerWindow: NSWindow?
    private var metalLayer: CAMetalLayer?
    private var commandQueue: MTLCommandQueue?
    private var keepAliveTimer: Timer?

    func potentialHeadroom(for display: CGDirectDisplayID) -> Double {
        guard let screen = DisplayManager.screen(for: display) else { return 1 }
        return Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
    }

    /// True while macOS is still raising the panel's headroom toward the requested boost.
    /// Callers keep calling `apply` each frame until this is false, so the boost glides in.
    var isHeadroomLimited: Bool { isActive && applied < requested - 0.001 }

    /// Applies a boost factor immediately (1 = off).
    func apply(factor: Double, display: CGDirectDisplayID) {
        self.display = display
        requested = max(1, factor)
        guard requested > 1.0005 else {
            deactivate()
            return
        }
        if !isActive { activate() }
        update()
    }

    /// Immediately removes the boost and restores the system colour tables.
    func reset() {
        requested = 1
        deactivate()
    }

    private func update() {
        let available = DisplayManager.screen(for: display)
            .map { Double($0.maximumExtendedDynamicRangeColorComponentValue) } ?? 1
        applied = min(requested, max(available, 1))
        applyGamma(applied)
    }

    // MARK: - Lifecycle

    private func activate() {
        guard let screen = DisplayManager.screen(for: display),
              let device = MTLCreateSystemDefaultDevice() else { return }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        layer.isOpaque = true
        layer.contentsScale = screen.backingScaleFactor
        layer.drawableSize = CGSize(width: screen.backingScaleFactor, height: screen.backingScaleFactor)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.layer = layer
        view.wantsLayer = true

        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .screenSaver
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.orderFrontRegardless()

        triggerWindow = window
        metalLayer = layer
        commandQueue = device.makeCommandQueue()
        baseTable = Self.readTable(display)
        isActive = true
        drawTrigger()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepAlive() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepAliveTimer = timer
    }

    private func deactivate() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        metalLayer = nil
        commandQueue = nil
        if isActive { CGDisplayRestoreColorSyncSettings() }
        isActive = false
        applied = 1
        baseTable = nil
    }

    private func keepAlive() {
        if PowerMonitor.isThermallyConstrained || PowerMonitor.isBatteryLow() {
            Log.brightness.notice("Boost dropped: safety stop (thermal state \(ProcessInfo.processInfo.thermalState.rawValue), battery low: \(PowerMonitor.isBatteryLow()))")
            reset()
            onSafetyStop?()
            return
        }
        // Night Shift, True Tone or other apps can rewrite the gamma table; re-assert ours.
        drawTrigger()
        update()
    }

    // MARK: - Rendering

    private func drawTrigger() {
        guard let layer = metalLayer, let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let v = max(2.0, requested)
        pass.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1)

        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    // macOS 26 rejects CGSetDisplayTransferByFormula values above 1.0 (kCGErrorIllegalArgument),
    // but CGSetDisplayTransferByTable accepts them.
    private func applyGamma(_ factor: Double) {
        guard isActive, let base = baseTable else { return }
        let f = Float(factor)
        var red = base.red.map { $0 * f }
        var green = base.green.map { $0 * f }
        var blue = base.blue.map { $0 * f }
        let result = CGSetDisplayTransferByTable(display, UInt32(red.count), &red, &green, &blue)
        if result != .success {
            NSLog("ProDisplay: CGSetDisplayTransferByTable failed (%d)", result.rawValue)
        }
    }

    private static func readTable(_ display: CGDirectDisplayID) -> (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
        let capacity = Int(CGDisplayGammaTableCapacity(display))
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = red, blue = red
        var count: UInt32 = 0
        if CGGetDisplayTransferByTable(display, UInt32(capacity), &red, &green, &blue, &count) == .success, count > 1 {
            let n = Int(count)
            return (Array(red.prefix(n)), Array(green.prefix(n)), Array(blue.prefix(n)))
        }
        let identity = (0..<256).map { CGGammaValue($0) / 255 }
        return (identity, identity, identity)
    }
}
