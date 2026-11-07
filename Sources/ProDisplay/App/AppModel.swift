import AppKit
import Observation
import ServiceManagement
import SwiftUI

@Observable
@MainActor
final class AppModel {
    // Display
    private(set) var builtinID: CGDirectDisplayID?
    /// Every display whose resolution can be changed, and the one the resolution controls act on.
    private(set) var displays: [DisplayInfo] = []
    private(set) var selectedDisplayID: CGDirectDisplayID?

    // Custom resolutions for the selected display.
    private(set) var customResolutions: [CustomResolution] = []
    private(set) var activeCustom: CustomResolution?
    private(set) var isApplyingCustom = false
    /// Pixel shape new custom sizes follow (below the notch on the built-in screen).
    private(set) var customAspect = CGSize(width: 16, height: 9)
    /// The selected display's default size, applied at launch and when it reconnects.
    private(set) var defaultResolution: DefaultResolution?
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
    var automaticallyChecksForUpdates: Bool {
        didSet { updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selectedDisplayID } }

    /// Sizes for the menu, one row each. By default only the display's native aspect ratio
    /// (not the built-in panel's below-notch variants); "Show other aspect ratios" adds the rest.
    var resolutionEntries: [ResolutionEntry] {
        let aspect = nativePixelSize.width / nativePixelSize.height
        return ResolutionEntry.merging(modeGroups).filter { entry in
            // While a custom size is on, the display reports it as one of its own modes;
            // it's already listed under Custom.
            if let activeCustom {
                if abs(entry.key.width - activeCustom.width) <= 2 && abs(entry.key.height - activeCustom.height) <= 2 { return false }
                let fullPanel = abs(Double(entry.key.width) / Double(entry.key.height) - aspect) < 0.01
                return showLowResolution || fullPanel
            }
            let fullPanel = abs(Double(entry.key.width) / Double(entry.key.height) - aspect) < 0.01
            return showLowResolution || fullPanel || entry.contains(currentKey)
        }
    }
    var currentEntry: ResolutionEntry? {
        ResolutionEntry.merging(modeGroups).first { $0.contains(currentKey) }
    }
    var isHiDPI: Bool {
        if let activeCustom { return activeCustom.hiDPI }
        return modeGroups.first { $0.key == currentKey }?.isHiDPI ?? true
    }
    /// The HiDPI switch only works when the current size exists in both versions.
    var canToggleHiDPI: Bool {
        guard activeCustom == nil else { return false }
        return currentEntry.map { $0.hiDPI != nil && $0.lowRes != nil } ?? false
    }
    /// The "looks like" size in use, custom or not.
    var currentSize: (width: Int, height: Int)? {
        if let activeCustom { return (activeCustom.width, activeCustom.height) }
        return currentKey.map { ($0.width, $0.height) }
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
    @ObservationIgnored private let updater = UpdaterService()
    @ObservationIgnored private let confirmPanel = ResolutionConfirmPanel()
    @ObservationIgnored private let custom = CustomResolutionService()
    /// Saved custom sizes and the one in use, keyed by `DisplayManager.persistentKey`.
    @ObservationIgnored private var savedCustom: [String: [CustomResolution]] = [:]
    @ObservationIgnored private var activeCustomByDisplay: [String: CustomResolution] = [:]
    /// Default sizes, keyed by `DisplayManager.persistentKey`.
    @ObservationIgnored private var defaultsByDisplay: [String: DefaultResolution] = [:]
    /// Displays seen so far, to apply a default or custom resolution when one appears.
    @ObservationIgnored private var knownDisplays: Set<CGDirectDisplayID> = []
    /// Displays a custom resolution is being switched on or off for right now.
    @ObservationIgnored private var customInFlight: Set<CGDirectDisplayID> = []
    /// The last mode the user kept on an external display, restored if a change isn't confirmed.
    @ObservationIgnored private var revertTarget: (display: CGDirectDisplayID, mode: CGDisplayMode)?
    @ObservationIgnored private var pollTimer: Timer?

    private enum Keys {
        static let showLowResolution = "showLowResolution"
        static let maxBoost = "maxBoost"
        static let brightnessKeysBoost = "brightnessKeysBoost"
        static let onboardingCompleted = "onboardingCompleted"
        static let volumeKeys = "volumeKeys"
        static let customResolutions = "customResolutions"
        static let activeCustomResolutions = "activeCustomResolutions"
        static let defaultResolutions = "defaultResolutions"
    }

    init() {
        showLowResolution = defaults.bool(forKey: Keys.showLowResolution)
        maxBoostSetting = defaults.object(forKey: Keys.maxBoost) as? Double ?? 1.6
        brightnessKeysBoost = defaults.object(forKey: Keys.brightnessKeysBoost) as? Bool ?? true
        volumeKeys = defaults.object(forKey: Keys.volumeKeys) as? Bool ?? true
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        defaults.removeObject(forKey: "customSizes") // left over from the first HiDPI scaling feature
        savedCustom = Self.decode(defaults.data(forKey: Keys.customResolutions)) ?? [:]
        activeCustomByDisplay = Self.decode(defaults.data(forKey: Keys.activeCustomResolutions)) ?? [:]
        defaultsByDisplay = Self.decode(defaults.data(forKey: Keys.defaultResolutions)) ?? [:]

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
        let list = DisplayManager.configurableDisplays()
        if list != displays { withAnimation(Theme.spring) { displays = list } }
        // Fall back to the built-in screen when the chosen display goes away.
        if !list.contains(where: { $0.id == selectedDisplayID }) {
            if let pending = revertTarget, pending.display == selectedDisplayID {
                confirmPanel.cancel()
                revertTarget = nil
            }
            selectedDisplayID = list.first?.id
        }
        custom.prune(keeping: list.map(\.id))
        loadModes()
        updateXDRAvailability()
        restoreResolutions(for: list)
    }

    /// When a display appears (at launch or on reconnect), switches it to its default size,
    /// or, without a default, brings back the custom resolution it last used.
    private func restoreResolutions(for list: [DisplayInfo]) {
        let ids = Set(list.map(\.id))
        let appeared = ids.subtracting(knownDisplays)
        knownDisplays = ids
        for id in appeared where custom.active(on: id) == nil && !customInFlight.contains(id) {
            let key = DisplayManager.persistentKey(for: id)
            switch defaultsByDisplay[key] {
            case .custom(let resolution):
                enableCustom(resolution, on: id)
            case .mode(let modeKey, let rate):
                // The default replaces whatever custom size was on when ProDisplay last quit.
                if activeCustomByDisplay.removeValue(forKey: key) != nil { saveCustom() }
                applyDefaultMode(modeKey, refreshRate: rate, to: id)
            case nil:
                if let resolution = activeCustomByDisplay[key] { enableCustom(resolution, on: id) }
            }
        }
    }

    /// Switches without asking "Keep this resolution?": the user already chose this mode as the default.
    private func applyDefaultMode(_ key: ModeKey, refreshRate: Double?, to id: CGDirectDisplayID) {
        if let current = modes.currentMode(for: id), ModeKey(current) == key,
           refreshRate.map({ abs(current.refreshRate - $0) < 0.01 }) ?? true {
            return
        }
        guard let mode = modes.groups(for: id).first(where: { $0.key == key })?.mode(refreshRate: refreshRate ?? -1) else {
            Log.brightness.notice("Default resolution \(key.width)×\(key.height) isn't offered by display \(id)")
            return
        }
        guard modes.apply(mode, to: id) else {
            Log.brightness.notice("macOS didn't accept the default resolution for display \(id)")
            return
        }
        // At launch this runs before the reconfiguration callback is registered.
        if id == selectedDisplayID { loadModes() }
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        guard id != selectedDisplayID, displays.contains(where: { $0.id == id }) else { return }
        withAnimation(Theme.spring) {
            selectedDisplayID = id
            loadModes()
        }
    }

    private func loadModes() {
        guard let id = selectedDisplayID else {
            modeGroups = []
            currentKey = nil
            customResolutions = []
            activeCustom = nil
            defaultResolution = nil
            return
        }
        customResolutions = savedCustom[DisplayManager.persistentKey(for: id)] ?? []
        defaultResolution = defaultsByDisplay[DisplayManager.persistentKey(for: id)]
        activeCustom = custom.active(on: id)

        let groups = modes.groups(for: id)
        let current = modes.currentMode(for: id)
        // The panel's real size is its largest 1× mode; HiDPI modes can render above it.
        if let native = groups.filter({ !$0.isHiDPI }).max(by: { $0.key.pixelWidth < $1.key.pixelWidth }) {
            nativePixelSize = CGSize(width: native.key.pixelWidth, height: native.key.pixelHeight)
            // On the built-in screen, mirrored content sits below the notch, so custom sizes use
            // that shape (the panel's tallest 1× mode that is shorter than the full panel).
            let belowNotch = CGDisplayIsBuiltin(id) != 0
                ? groups.filter { !$0.isHiDPI && $0.key.pixelWidth == native.key.pixelWidth && $0.key.pixelHeight < native.key.pixelHeight }
                    .max { $0.key.pixelHeight < $1.key.pixelHeight }
                : nil
            let shape = belowNotch?.key ?? native.key
            customAspect = CGSize(width: shape.pixelWidth, height: shape.pixelHeight)
        }
        withAnimation(Theme.spring) {
            modeGroups = groups
            currentKey = current.map(ModeKey.init)
            currentRefresh = current?.refreshRate ?? 0
        }
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
        guard let id = selectedDisplayID, let mode = group.mode(refreshRate: currentRefresh) else { return }
        withAnimation(Theme.spring) { currentKey = group.key }
        guard activeCustom != nil else { return apply(mode, to: id) }
        // Leave the custom resolution first; the display's own modes apply once it is gone.
        withAnimation(Theme.spring) { activeCustom = nil }
        isApplyingCustom = true
        Task {
            await custom.disable(on: id)
            activeCustomByDisplay[DisplayManager.persistentKey(for: id)] = nil
            saveCustom()
            isApplyingCustom = false
            apply(mode, to: id)
            refreshDisplays()
        }
    }

    // MARK: - Custom resolutions

    /// Valid widths for a new custom size on the selected display.
    func customWidthRange(hiDPI: Bool) -> ClosedRange<Int> {
        // Virtual displays top out around 8K pixels wide.
        let maxPixels = 7680
        return 640...(hiDPI ? maxPixels / 2 : maxPixels)
    }

    func customHeight(forWidth width: Int) -> Int {
        Int((Double(width) * customAspect.height / customAspect.width).rounded())
    }

    /// Saves a new size for the selected display and switches to it.
    func addCustom(width: Int, hiDPI: Bool) {
        guard let id = selectedDisplayID, customWidthRange(hiDPI: hiDPI).contains(width) else { return }
        let resolution = CustomResolution(width: width, height: customHeight(forWidth: width), hiDPI: hiDPI)
        let key = DisplayManager.persistentKey(for: id)
        var list = savedCustom[key] ?? []
        if !list.contains(resolution) {
            list.append(resolution)
            list.sort { ($0.width, $0.hiDPI ? 1 : 0) > ($1.width, $1.hiDPI ? 1 : 0) }
        }
        savedCustom[key] = list
        saveCustom()
        withAnimation(Theme.spring) { customResolutions = list }
        selectCustom(resolution)
    }

    func selectCustom(_ resolution: CustomResolution) {
        guard let id = selectedDisplayID, resolution != activeCustom, !isApplyingCustom else { return }
        enableCustom(resolution, on: id)
    }

    func removeCustom(_ resolution: CustomResolution) {
        guard let id = selectedDisplayID else { return }
        let key = DisplayManager.persistentKey(for: id)
        if defaultResolution == .custom(resolution) { clearDefault() }
        savedCustom[key]?.removeAll { $0 == resolution }
        if savedCustom[key]?.isEmpty == true { savedCustom[key] = nil }
        withAnimation(Theme.spring) { customResolutions = savedCustom[key] ?? [] }
        if activeCustom == resolution {
            withAnimation(Theme.spring) { activeCustom = nil }
            activeCustomByDisplay[key] = nil
            isApplyingCustom = true
            Task {
                await custom.disable(on: id)
                isApplyingCustom = false
                refreshDisplays()
            }
        }
        saveCustom()
    }

    private func enableCustom(_ resolution: CustomResolution, on id: CGDirectDisplayID) {
        let key = DisplayManager.persistentKey(for: id)
        let refresh = modeGroups.flatMap(\.refreshRates).max() ?? 60
        if id == selectedDisplayID { withAnimation(Theme.spring) { activeCustom = resolution } }
        isApplyingCustom = true
        customInFlight.insert(id)
        Task {
            defer { customInFlight.remove(id) }
            do {
                try await custom.enable(resolution, on: id, refreshRate: refresh)
                activeCustomByDisplay[key] = resolution
            } catch {
                // Don't retry a size that fails on every launch.
                activeCustomByDisplay[key] = nil
                withAnimation(Theme.spring) { errorMessage = error.localizedDescription }
            }
            saveCustom()
            isApplyingCustom = false
            refreshDisplays()
        }
    }

    // MARK: - Default resolution

    func isDefault(_ entry: ResolutionEntry) -> Bool {
        if case .mode(let key, _) = defaultResolution { return entry.contains(key) }
        return false
    }

    func isDefault(_ resolution: CustomResolution) -> Bool {
        defaultResolution == .custom(resolution)
    }

    /// Makes a size the selected display's default, or clears it if it already is.
    /// Uses the version the row shows (current, else the one the HiDPI switch picks).
    func toggleDefault(_ entry: ResolutionEntry) {
        guard !isDefault(entry) else { return clearDefault() }
        let group = entry.variants.first { $0.key == currentKey } ?? entry.variant(hiDPI: isHiDPI)
        // Keep the refresh rate in use for the current size; otherwise take the highest.
        let rate = group.key == currentKey && activeCustom == nil ? currentRefresh : nil
        setDefault(.mode(group.key, refreshRate: rate))
    }

    func toggleDefault(_ resolution: CustomResolution) {
        isDefault(resolution) ? clearDefault() : setDefault(.custom(resolution))
    }

    func clearDefault() { setDefault(nil) }

    private func setDefault(_ value: DefaultResolution?) {
        guard let id = selectedDisplayID else { return }
        defaultsByDisplay[DisplayManager.persistentKey(for: id)] = value
        defaults.set(try? JSONEncoder().encode(defaultsByDisplay), forKey: Keys.defaultResolutions)
        withAnimation(Theme.spring) { defaultResolution = value }
    }

    private func saveCustom() {
        defaults.set(try? JSONEncoder().encode(savedCustom), forKey: Keys.customResolutions)
        defaults.set(try? JSONEncoder().encode(activeCustomByDisplay), forKey: Keys.activeCustomResolutions)
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func selectRefresh(_ rate: Double) {
        guard let id = selectedDisplayID,
              let mode = modeGroups.first(where: { $0.key == currentKey })?.mode(refreshRate: rate)
        else { return }
        withAnimation(Theme.spring) { currentRefresh = rate }
        apply(mode, to: id)
    }

    /// The built-in panel supports every mode it lists. An external monitor may not, and a mode
    /// it can't show leaves it black, so external changes revert unless the user keeps them.
    private func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) {
        let previous = modes.currentMode(for: id)
        guard modes.apply(mode, to: id) else {
            withAnimation(Theme.spring) { errorMessage = "macOS didn't accept that mode." }
            refreshDisplays()
            return
        }
        guard CGDisplayIsBuiltin(id) == 0 else { return }

        // Several changes in a row revert to the mode from before the first one.
        if revertTarget?.display != id, let previous {
            revertTarget = (id, previous)
        }
        confirmPanel.show(on: id, keep: { [weak self] in
            self?.revertTarget = nil
        }, revert: { [weak self] in
            guard let self, let target = self.revertTarget else { return }
            self.revertTarget = nil
            self.modes.apply(target.mode, to: target.display)
            self.refreshDisplays()
        })
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

    func checkForUpdates() {
        updater.checkForUpdates()
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
