import CoreGraphics
import Foundation
import QuartzCore

/// Animates brightness along one continuous 0...2 scale: 0–1 is system brightness,
/// 1–2 is the XDR boost. Every change eases in over time instead of jumping, and
/// crossing 100% hands over from system brightness to the boost without a seam.
@MainActor
final class BrightnessController {
    let xdr = XDRBrightnessService()

    private(set) var current: Double
    private var target: Double
    private var display: CGDirectDisplayID = 0
    private var maxBoost = 1.0
    private var lastSystem: Double?

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// Easing time constant: a change is about 95% done after 3× this.
    private let timeConstant = 0.08

    var isAnimating: Bool { timer != nil }

    init(level: Double = 0.5) {
        current = level
        target = level
    }

    func setTarget(_ level: Double, display: CGDirectDisplayID, maxBoost: Double) {
        self.display = display
        self.maxBoost = maxBoost
        target = level
        startTimer()
    }

    /// Adopts a level changed outside ProDisplay (Control Center, auto-brightness)
    /// without applying anything.
    func sync(to level: Double) {
        guard !isAnimating else { return }
        current = level
        target = level
        lastSystem = level <= 1 ? level : 1
    }

    /// Drops any boost at once (safety stop, quitting).
    func resetBoost() {
        xdr.reset()
        if current > 1 { current = 1 }
        if target > 1 { target = 1 }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        // 120 Hz to match ProMotion; .common keeps it running while dragging or menus track the mouse.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now

        // Time-based exponential easing: smooth, frame-rate independent, and retargets
        // mid-flight without a kink when keys are pressed repeatedly.
        current += (target - current) * (1 - exp(-dt / timeConstant))
        if abs(target - current) < 0.0005 { current = target }
        apply(current)

        if current == target, !xdr.isHeadroomLimited {
            timer?.invalidate()
            timer = nil
        }
    }

    private func apply(_ level: Double) {
        let system = min(max(level, 0), 1)
        if lastSystem.map({ abs($0 - system) > 0.0001 }) ?? true {
            BrightnessService.setBrightness(system, of: display)
            lastSystem = system
        }
        let factor = level > 1 ? 1 + (level - 1) * (maxBoost - 1) : 1
        xdr.apply(factor: factor, display: display)
    }
}
