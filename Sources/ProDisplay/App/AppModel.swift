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
    private(set) var keyAccessGranted = MediaKeyMonitor.isTrusted

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
            updateKeyMonitor(prompt: true)
        }
    }
    var volumeKeys: Bool {
        didSet {
            defaults.set(volumeKeys, forKey: Keys.volumeKeys)
            updateKeyMonitor(prompt: true)
        }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    /// Sizes for the menu, one row each. By default only the full panel's aspect ratio
    /// (not the below-notch variants); "show all" adds the rest.
    var resolutionEntries: [ResolutionEntry] {
        let aspect = nativePixelSize.width / nativePixelSize.height
        return ResolutionEntry.merging(modeGroups).filter { entry in
            let fullPanel = abs(Double(entry.key.width) / Double(entry.key.height) - aspect) < 0.01
            return showLowResolution || fullPanel || entry.contains(currentKey)
        }
    }
    var currentEntry: ResolutionEntry? {
        ResolutionEntry.merging(modeGroups).first { $0.contains(currentKey) }
    }
    var isHiDPI: Bool {
        modeGroups.first { $0.key == currentKey }?.isHiDPI ?? true
    }
    /// The HiDPI switch only works when the current size exists in both versions.
    var canToggleHiDPI: Bool {
        currentEntry.map { $0.hiDPI != nil && $0.lowRes != nil } ?? false
    }
    var refreshRates: [Double] {
        modeGroups.first { $0.key == currentKey }?.refreshRates ?? []
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let modes = DisplayModeService()
    @ObservationIgnored private let brightness = BrightnessController()
    @ObservationIgnored private let keyMonitor = MediaKeyMonitor()
    @ObservationIgnored private let osd = LevelOSD()
    @ObservationIgnored private let onboarding = OnboardingWindow()
    @ObservationIgnored private var pollTimer: Timer?

    private enum Keys {
        static let showLowResolution = "showLowResolution"
        static let maxBoost = "maxBoost"
        static let brightnessKeysBoost = "brightnessKeysBoost"
        static let onboardingCompleted = "onboardingCompleted"
        static let volumeKeys = "volumeKeys"
    }

    init() {
        showLowResolution = defaults.bool(forKey: Keys.showLowResolution)
        maxBoostSetting = defaults.object(forKey: Keys.maxBoost) as? Double ?? 1.6
        brightnessKeysBoost = defaults.object(forKey: Keys.brightnessKeysBoost) as? Bool ?? true
        volumeKeys = defaults.object(forKey: Keys.volumeKeys) as? Bool ?? true
        defaults.removeObject(forKey: "customSizes") // left over from the removed HiDPI scaling feature

        refreshDisplays()
        if let id = builtinID, let b = BrightnessService.brightness(of: id) {
            sliderValue = b
            brightness.sync(to: b)
        }

        brightness.xdr.onSafetyStop = { [weak self] in self?.boostStoppedForSafety() }

        keyMonitor.handler = { [weak self] key, fine in self?.handleMediaKey(key, fine: fine) ?? false }
        keyMonitor.onTrustChange = { [weak self] granted in self?.keyAccessGranted = granted }
        // On first launch the onboarding explains the permission before macOS asks for it.
        let onboarded = defaults.bool(forKey: Keys.onboardingCompleted)
        updateKeyMonitor(prompt: onboarded)
        if !onboarded {
            Task { @MainActor [weak self] in self?.showOnboarding() }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            Log.brightness.notice("Display reconfigured: flags \(flags.rawValue, format: .hex)")
            let model = Unmanaged<AppModel>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in model.refreshDisplays() }
        }, context)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.brightness.resetBoost() }
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

    /// Picks a size, keeping the current HiDPI choice when that size allows it.
    func select(_ entry: ResolutionEntry) {
        select(entry.variant(hiDPI: isHiDPI))
    }

    func setHiDPI(_ on: Bool) {
        guard let entry = currentEntry, canToggleHiDPI else { return }
        select(entry.variant(hiDPI: on))
    }

    func select(_ group: DisplayModeGroup) {
        guard let id = builtinID, let mode = group.mode(refreshRate: currentRefresh) else { return }
        withAnimation(Theme.spring) { currentKey = group.key }
        modes.apply(mode, to: id)
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
        brightness.setTarget(v, display: id, maxBoost: maxBoost)
    }

    func boostFactor(for value: Double) -> Double {
        1 + max(0, value - 1) * (maxBoost - 1)
    }

    private func updateKeyMonitor(prompt: Bool) {
        brightnessKeysBoost || volumeKeys ? keyMonitor.start(prompt: prompt) : keyMonitor.stop()
    }

    /// Returns true when ProDisplay handled the key (macOS won't see it).
    private func handleMediaKey(_ key: MediaKey, fine: Bool) -> Bool {
        switch key {
        case .brightnessUp: handleBrightnessKey(up: true, fine: fine)
        case .brightnessDown: handleBrightnessKey(up: false, fine: fine)
        case .volumeUp: handleVolumeKey(up: true, fine: fine)
        case .volumeDown: handleVolumeKey(up: false, fine: fine)
        case .mute: handleMuteKey()
        }
    }

    /// Brightness keys: ProDisplay handles the whole 0–200% range and shows its own indicator.
    /// Returns true when ProDisplay handled the key (macOS won't see it).
    private func handleBrightnessKey(up: Bool, fine: Bool) -> Bool {
        guard brightnessKeysBoost, let id = builtinID else { return false }
        // Same step sizes as macOS: 16 steps (or 64 with ⌥⇧) up to 100%, then 8 (or 32) for XDR.
        let sdrStep = fine ? 1.0 / 64 : 1.0 / 16
        let xdrStep = fine ? 1.0 / 32 : 1.0 / 8
        let top = xdrAvailable ? 2.0 : 1.0
        // Mid-fade, the slider holds the destination; otherwise trust the live system value.
        var v = sliderValue > 1 || brightness.isAnimating
            ? sliderValue
            : (BrightnessService.brightness(of: id) ?? sliderValue)

        if up {
            v = v < 1 ? min(1, v + sdrStep) : min(top, v + xdrStep)
        } else {
            v = v > 1 ? max(1, v - xdrStep) : max(0, v - sdrStep)
        }
        withAnimation(Theme.spring) { setSlider(v) }

        let percent = sliderValue > 1 ? boostFactor(for: sliderValue) * 100 : sliderValue * 100
        osd.showBrightness(
            value: sliderValue,
            xdrAvailable: xdrAvailable,
            percent: Int(percent.rounded()),
            on: DisplayManager.screen(for: id)
        )
        return true
    }

    /// Volume keys: same 16 steps as macOS (64 with ⌥⇧). Outputs whose volume
    /// can't be set (some HDMI devices) are left to macOS.
    private func handleVolumeKey(up: Bool, fine: Bool) -> Bool {
        guard volumeKeys, let device = VolumeService.defaultOutputDevice,
              VolumeService.canSetVolume(device),
              let current = VolumeService.volume(of: device) else { return false }

        let step = fine ? 1.0 / 64 : 1.0 / 16
        let level = min(max(current + (up ? step : -step), 0), 1)
        VolumeService.setVolume(level, of: device)
        // Like macOS: changing the volume unmutes, and reaching zero mutes.
        VolumeService.setMuted(level == 0, of: device)
        osd.showVolume(level: level, muted: level == 0, on: NSScreen.main)
        return true
    }

    private func handleMuteKey() -> Bool {
        guard volumeKeys, let device = VolumeService.defaultOutputDevice,
              VolumeService.canSetVolume(device) else { return false }
        let muted = !VolumeService.isMuted(device)
        VolumeService.setMuted(muted, of: device)
        osd.showVolume(level: VolumeService.volume(of: device) ?? 0, muted: muted, on: NSScreen.main)
        return true
    }

    func showOnboarding() {
        onboarding.show(model: self) { [weak self] in
            self?.defaults.set(true, forKey: Keys.onboardingCompleted)
        }
    }

    func openAccessibilitySettings() {
        keyMonitor.start(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func pollBrightness() {
        // Only watch for changes made outside ProDisplay (Control Center, auto-brightness);
        // while ProDisplay is fading, the system value is mid-flight and would fight the fade.
        guard !isDraggingSlider, !brightness.isAnimating, let id = builtinID,
              let b = BrightnessService.brightness(of: id) else { return }

        if sliderValue > 1 {
            // Lowered elsewhere while boosted: hand control back to the system.
            if b < 0.98 {
                Log.brightness.notice("Boost dropped: system brightness changed outside ProDisplay to \(b, format: .fixed(precision: 3)) (slider \(self.sliderValue, format: .fixed(precision: 3)))")
                brightness.resetBoost()
                brightness.sync(to: b)
                withAnimation(Theme.spring) { sliderValue = b }
            }
        } else if abs(b - sliderValue) > 0.005 {
            brightness.sync(to: b)
            withAnimation(Theme.spring) { sliderValue = b }
        }
        updateXDRAvailability()
    }

    private func updateXDRAvailability() {
        guard let id = builtinID else { return }
        potentialHeadroom = brightness.xdr.potentialHeadroom(for: id)
        let boost = min(potentialHeadroom, maxBoostSetting)
        if boost != maxBoost {
            maxBoost = boost
            if sliderValue > 1 { brightness.setTarget(sliderValue, display: id, maxBoost: boost) }
        }
        let available = boost > 1.01
        if available != xdrAvailable {
            withAnimation(Theme.spring) { xdrAvailable = available }
        }
        if !available, sliderValue > 1 {
            Log.brightness.notice("Boost dropped: XDR unavailable (potential headroom \(self.potentialHeadroom, format: .fixed(precision: 2)), built-in screen found: \(DisplayManager.screen(for: id) != nil), limit \(self.maxBoostSetting, format: .fixed(precision: 2)))")
            brightness.setTarget(1, display: id, maxBoost: maxBoost)
            withAnimation(Theme.spring) { sliderValue = 1 }
        }
    }

    private func boostStoppedForSafety() {
        brightness.resetBoost()
        withAnimation(Theme.spring) {
            sliderValue = 1
            errorMessage = PowerMonitor.isThermallyConstrained
                ? "XDR boost paused: the Mac is running hot."
                : "XDR boost paused: battery is low."
        }
    }

    func clearError() {
        withAnimation(Theme.spring) { errorMessage = nil }
    }
}
