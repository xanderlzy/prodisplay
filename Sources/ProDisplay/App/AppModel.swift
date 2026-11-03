import AppKit
import Observation
import ServiceManagement
import SwiftUI

@Observable
@MainActor
final class AppModel {
    // Display
    private(set) var builtinID: CGDirectDisplayID?
    private(set) var modeGroups: [DisplayModeGroup] = []
    private(set) var currentKey: ModeKey?
    private(set) var currentRefresh: Double = 0
    private(set) var nativePixelSize = CGSize(width: 3456, height: 2234)

    // Brightness: 0...1 is system brightness, 1...2 is the XDR boost range.
    private(set) var sliderValue: Double = 0.5
    private(set) var xdrAvailable = false
    private(set) var maxBoost: Double = 1
    private(set) var potentialHeadroom: Double = 1
    var isDraggingSlider = false
    private(set) var keyAccessGranted = BrightnessKeyMonitor.isTrusted

    // Scaling
    private(set) var activeCustom: CustomSize?
    private(set) var applyingCustom: CustomSize?
    private(set) var errorMessage: String?

    var showLowResolution: Bool {
        didSet { defaults.set(showLowResolution, forKey: Keys.showLowResolution) }
    }
    var maxBoostSetting: Double {
        didSet {
            defaults.set(maxBoostSetting, forKey: Keys.maxBoost)
            updateXDRAvailability()
        }
    }
    var brightnessKeysBoost: Bool {
        didSet {
            defaults.set(brightnessKeysBoost, forKey: Keys.brightnessKeysBoost)
            brightnessKeysBoost ? keyMonitor.start(prompt: true) : keyMonitor.stop()
        }
    }
    var customSizes: [CustomSize] {
        didSet { defaults.set(try? JSONEncoder().encode(customSizes), forKey: Keys.customSizes) }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    var visibleGroups: [DisplayModeGroup] {
        // By default: HiDPI modes with the full panel's aspect ratio (not the below-notch variants).
        let aspect = nativePixelSize.width / nativePixelSize.height
        return modeGroups.filter { group in
            let fullPanel = abs(Double(group.key.width) / Double(group.key.height) - aspect) < 0.01
            return showLowResolution || (group.isHiDPI && fullPanel) || group.key == currentKey
        }
    }
    var refreshRates: [Double] {
        modeGroups.first { $0.key == currentKey }?.refreshRates ?? []
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let modes = DisplayModeService()
    @ObservationIgnored private let xdr = XDRBrightnessService()
    @ObservationIgnored private let hidpi = VirtualHiDPIService()
    @ObservationIgnored private let confirm = ConfirmHUD()
    @ObservationIgnored private let keyMonitor = BrightnessKeyMonitor()
    @ObservationIgnored private let osd = BrightnessOSD()
    @ObservationIgnored private var pollTimer: Timer?

    private enum Keys {
        static let showLowResolution = "showLowResolution"
        static let maxBoost = "maxBoost"
        static let customSizes = "customSizes"
        static let brightnessKeysBoost = "brightnessKeysBoost"
    }

    init() {
        showLowResolution = defaults.bool(forKey: Keys.showLowResolution)
        maxBoostSetting = defaults.object(forKey: Keys.maxBoost) as? Double ?? 1.6
        brightnessKeysBoost = defaults.object(forKey: Keys.brightnessKeysBoost) as? Bool ?? true
        customSizes = (defaults.data(forKey: Keys.customSizes))
            .flatMap { try? JSONDecoder().decode([CustomSize].self, from: $0) } ?? []

        refreshDisplays()
        if let id = builtinID, let b = BrightnessService.brightness(of: id) { sliderValue = b }
        if customSizes.isEmpty { customSizes = suggestedSizes() }

        xdr.onSafetyStop = { [weak self] in self?.boostStoppedForSafety() }

        keyMonitor.handler = { [weak self] up, fine in self?.handleBrightnessKey(up: up, fine: fine) ?? false }
        keyMonitor.onTrustChange = { [weak self] granted in self?.keyAccessGranted = granted }
        if brightnessKeysBoost { keyMonitor.start(prompt: true) }

        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            let model = Unmanaged<AppModel>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in model.refreshDisplays() }
        }, context)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.xdr.reset() }
        }
    }

    // MARK: - Displays & resolutions

    func refreshDisplays() {
        builtinID = DisplayManager.builtinDisplayID()
        guard let id = builtinID else { return }

        let groups = modes.groups(for: id)
        let current = modes.currentMode(for: id)
        // The panel's real size is its largest 1× mode; HiDPI modes can render above it.
        if let native = groups.filter({ !$0.isHiDPI }).max(by: { $0.key.pixelWidth < $1.key.pixelWidth }) {
            nativePixelSize = CGSize(width: native.key.pixelWidth, height: native.key.pixelHeight)
        }
        withAnimation(Theme.spring) {
            modeGroups = groups
            currentKey = current.map(ModeKey.init)
            currentRefresh = current?.refreshRate ?? 0
        }
        updateXDRAvailability()
    }

    func select(_ group: DisplayModeGroup) {
        Task {
            if activeCustom != nil { await disableCustom() }
            guard let id = builtinID, let mode = group.mode(refreshRate: currentRefresh) else { return }
            withAnimation(Theme.spring) { currentKey = group.key }
            modes.apply(mode, to: id)
        }
    }

    func selectRefresh(_ rate: Double) {
        guard let id = builtinID,
              let mode = modeGroups.first(where: { $0.key == currentKey })?.mode(refreshRate: rate)
        else { return }
        withAnimation(Theme.spring) { currentRefresh = rate }
        modes.apply(mode, to: id)
    }

    // MARK: - Brightness

    func setSlider(_ value: Double) {
        guard let id = builtinID else { return }
        let v = xdrAvailable ? min(max(value, 0), 2) : min(max(value, 0), 1)
        sliderValue = v

        if v <= 1 {
            xdr.setBoost(1, display: id)
            BrightnessService.setBrightness(v, of: id)
        } else {
            if (BrightnessService.brightness(of: id) ?? 1) < 0.999 {
                BrightnessService.setBrightness(1, of: id)
            }
            xdr.setBoost(boostFactor(for: v), display: id)
        }
    }

    func boostFactor(for value: Double) -> Double {
        1 + max(0, value - 1) * (maxBoost - 1)
    }

    /// Brightness keys: ProDisplay handles the whole 0–200% range and shows its own indicator.
    /// Returns true when ProDisplay handled the key (macOS won't see it).
    private func handleBrightnessKey(up: Bool, fine: Bool) -> Bool {
        guard brightnessKeysBoost, let id = builtinID else { return false }
        // Same step sizes as macOS: 16 steps (or 64 with ⌥⇧) up to 100%, then 8 (or 32) for XDR.
        let sdrStep = fine ? 1.0 / 64 : 1.0 / 16
        let xdrStep = fine ? 1.0 / 32 : 1.0 / 8
        let top = xdrAvailable ? 2.0 : 1.0
        var v = sliderValue > 1 ? sliderValue : (BrightnessService.brightness(of: id) ?? sliderValue)

        if up {
            v = v < 1 ? min(1, v + sdrStep) : min(top, v + xdrStep)
        } else {
            v = v > 1 ? max(1, v - xdrStep) : max(0, v - sdrStep)
        }
        withAnimation(Theme.spring) { setSlider(v) }

        let percent = sliderValue > 1 ? boostFactor(for: sliderValue) * 100 : sliderValue * 100
        osd.show(
            value: sliderValue,
            xdrAvailable: xdrAvailable,
            percent: Int(percent.rounded()),
            on: DisplayManager.screen(for: id)
        )
        return true
    }

    func openAccessibilitySettings() {
        keyMonitor.start(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func pollBrightness() {
        guard !isDraggingSlider, let id = builtinID,
              let b = BrightnessService.brightness(of: id) else { return }

        if sliderValue > 1 {
            // Brightness keys pressed while boosted: hand control back to the system.
            if b < 0.98 {
                xdr.setBoost(1, display: id)
                withAnimation(Theme.spring) { sliderValue = b }
            }
        } else if abs(b - sliderValue) > 0.005 {
            withAnimation(Theme.spring) { sliderValue = b }
        }
        updateXDRAvailability()
    }

    private func updateXDRAvailability() {
        guard let id = builtinID else { return }
        potentialHeadroom = xdr.potentialHeadroom(for: id)
        let boost = min(potentialHeadroom, maxBoostSetting)
        if boost != maxBoost { maxBoost = boost }
        let available = boost > 1.01
        if available != xdrAvailable {
            withAnimation(Theme.spring) { xdrAvailable = available }
        }
        if !available, sliderValue > 1 {
            xdr.setBoost(1, display: id)
            withAnimation(Theme.spring) { sliderValue = 1 }
        }
    }

    private func boostStoppedForSafety() {
        withAnimation(Theme.spring) {
            sliderValue = 1
            errorMessage = PowerMonitor.isThermallyConstrained
                ? "XDR boost paused: the Mac is running hot."
                : "XDR boost paused: battery is low."
        }
    }

    // MARK: - Custom HiDPI scaling

    func applyCustom(_ size: CustomSize) {
        guard let id = builtinID, applyingCustom == nil, activeCustom != size else { return }
        xdr.reset()
        if sliderValue > 1 { sliderValue = 1 }

        withAnimation(Theme.spring) {
            applyingCustom = size
            errorMessage = nil
        }
        let previous = activeCustom
        Task {
            do {
                try await hidpi.enable(size, builtin: id)
                withAnimation(Theme.spring) { activeCustom = size }
                confirm.show(size: size) { [weak self] in
                    guard let self else { return }
                    if let previous { self.applyCustom(previous) } else { Task { await self.disableCustom() } }
                }
            } catch {
                withAnimation(Theme.spring) {
                    activeCustom = nil
                    errorMessage = error.localizedDescription
                }
            }
            withAnimation(Theme.spring) { applyingCustom = nil }
        }
    }

    func disableCustom() async {
        guard let id = builtinID else { return }
        confirm.dismiss()
        await hidpi.disable(builtin: id)
        withAnimation(Theme.spring) { activeCustom = nil }
        refreshDisplays()
    }

    func addCustomSize(width: Int) {
        let size = CustomSize(width: width, height: height(forWidth: width))
        guard width >= 800, !customSizes.contains(size) else { return }
        withAnimation(Theme.spring) {
            customSizes.append(size)
            customSizes.sort { $0.width < $1.width }
        }
    }

    func removeCustomSize(_ size: CustomSize) {
        withAnimation(Theme.spring) { customSizes.removeAll { $0 == size } }
    }

    func height(forWidth width: Int) -> Int {
        let h = Double(width) * nativePixelSize.height / nativePixelSize.width
        return Int((h / 2).rounded()) * 2
    }

    /// Sizes larger than the biggest HiDPI size macOS offers, skipping ones it already has.
    private func suggestedSizes() -> [CustomSize] {
        let existing = modeGroups.filter(\.isHiDPI).map { Double($0.key.width) }
        let largest = existing.max() ?? nativePixelSize.width / 2
        return [1.05, 1.1, 1.15, 1.2]
            .map { Int((largest * $0 / 2).rounded()) * 2 }
            .filter { w in !existing.contains { abs($0 - Double(w)) / Double(w) < 0.015 } }
            .map { CustomSize(width: $0, height: height(forWidth: $0)) }
    }

    func clearError() {
        withAnimation(Theme.spring) { errorMessage = nil }
    }
}
