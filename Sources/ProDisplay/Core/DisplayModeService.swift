import CoreGraphics

struct ModeKey: Hashable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int

    init(_ mode: CGDisplayMode) {
        width = mode.width
        height = mode.height
        pixelWidth = mode.pixelWidth
        pixelHeight = mode.pixelHeight
    }
}

struct DisplayModeGroup: Identifiable {
    let key: ModeKey
    let modes: [CGDisplayMode]
    let isDefault: Bool

    var id: ModeKey { key }
    var isHiDPI: Bool { key.pixelWidth > key.width }
    var refreshRates: [Double] { Array(Set(modes.map(\.refreshRate))).sorted(by: >) }

    func mode(refreshRate: Double) -> CGDisplayMode? {
        modes.first { abs($0.refreshRate - refreshRate) < 0.01 } ?? modes.max { $0.refreshRate < $1.refreshRate }
    }
}

struct DisplayModeService {
    private static let defaultModeFlag: UInt32 = 0x0000_0004 // kDisplayModeDefaultFlag

    func groups(for display: CGDirectDisplayID) -> [DisplayModeGroup] {
        // Includes the "duplicate" low-resolution modes System Settings hides.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }

        return Dictionary(grouping: modes, by: ModeKey.init)
            .map { key, modes in
                DisplayModeGroup(
                    key: key,
                    modes: modes,
                    isDefault: modes.contains { $0.ioFlags & Self.defaultModeFlag != 0 }
                )
            }
            .sorted {
                ($0.key.width, $0.key.pixelWidth) > ($1.key.width, $1.key.pixelWidth)
            }
    }

    func currentMode(for display: CGDirectDisplayID) -> CGDisplayMode? {
        CGDisplayCopyDisplayMode(display)
    }

    @discardableResult
    func apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
