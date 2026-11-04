import AppKit
import ApplicationServices

enum MediaKey {
    case brightnessUp, brightnessDown, volumeUp, volumeDown, mute
}

/// Intercepts the hardware brightness (F1/F2) and volume (F10–F12) keys with an event tap.
/// `handler` decides per key press whether ProDisplay takes it (true) or macOS does (false);
/// `fine` is true when ⌥⇧ is held (quarter steps, like macOS).
@MainActor
final class MediaKeyMonitor {
    var handler: ((_ key: MediaKey, _ fine: Bool) -> Bool)?
    var onTrustChange: ((Bool) -> Void)?

    private(set) var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    /// Key codes whose key-down was swallowed, so the matching key-up is swallowed too.
    private var swallowed: Set<Int> = []

    private static let systemDefinedType: UInt32 = 14 // NX_SYSDEFINED
    private static let auxControlButtons: Int16 = 8   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    private static let keys: [Int: MediaKey] = [
        0: .volumeUp,       // NX_KEYTYPE_SOUND_UP
        1: .volumeDown,     // NX_KEYTYPE_SOUND_DOWN
        2: .brightnessUp,   // NX_KEYTYPE_BRIGHTNESS_UP
        3: .brightnessDown, // NX_KEYTYPE_BRIGHTNESS_DOWN
        7: .mute,           // NX_KEYTYPE_MUTE
    ]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    func start(prompt: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), install() {
            retryTimer?.invalidate()
            retryTimer = nil
            onTrustChange?(true)
        } else {
            onTrustChange?(false)
            scheduleRetry()
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
        swallowed.removeAll()
    }

    /// Waits for the user to grant Accessibility access, then installs the tap.
    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Self.isTrusted else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.start(prompt: false)
            }
        }
    }

    private func install() -> Bool {
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                // The tap is on the main run loop, so this runs on the main thread.
                let swallow = MainActor.assumeIsolated { monitor.process(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func process(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == Self.systemDefinedType,
              let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == Self.auxControlButtons
        else { return false }

        let code = (ns.data1 & 0xFFFF_0000) >> 16
        guard let key = Self.keys[code] else { return false }
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA

        guard isDown else { return swallowed.remove(code) != nil }
        let fine = ns.modifierFlags.isSuperset(of: [.option, .shift])
        if handler?(key, fine) == true {
            swallowed.insert(code)
            return true
        }
        swallowed.remove(code)
        return false
    }
}
