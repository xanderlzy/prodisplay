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

/// One "looks like" size in the menu: its HiDPI and low-resolution versions merged.
/// macOS sometimes offers the two versions a point apart (2298 × 1492 vs 2298 × 1493,
/// 2420 × 1572 vs 2419 × 1571), so sizes within 2 points count as the same.
struct ResolutionEntry: Identifiable {
    let variants: [DisplayModeGroup]

    var hiDPI: DisplayModeGroup? { variants.first(where: \.isHiDPI) }
    var lowRes: DisplayModeGroup? { variants.first { !$0.isHiDPI } }
    /// Labelled by the HiDPI version when there is one.
    var key: ModeKey { (hiDPI ?? variants[0]).key }
    var id: String { "\(key.width)x\(key.height)" }
    var isDefault: Bool { variants.contains(where: \.isDefault) }

    func contains(_ key: ModeKey?) -> Bool { variants.contains { $0.key == key } }

    /// The version to use for a HiDPI preference, falling back to whichever exists.
    func variant(hiDPI wantHiDPI: Bool) -> DisplayModeGroup {
        (wantHiDPI ? hiDPI ?? lowRes : lowRes ?? hiDPI) ?? variants[0]
    }

    static func merging(_ groups: [DisplayModeGroup]) -> [ResolutionEntry] {
        var entries: [[DisplayModeGroup]] = []
        for group in groups.sorted(by: { ($0.key.width, $0.key.height) > ($1.key.width, $1.key.height) }) {
            // Compare with every row, not just the previous one: other aspect ratios
            // (e.g. below-notch sizes) can sort between two twins.
            if let i = entries.firstIndex(where: { row in
                row.contains { abs($0.key.width - group.key.width) <= 2 && abs($0.key.height - group.key.height) <= 2 }
            }) {
                entries[i].append(group)
            } else {
                entries.append([group])
            }
        }
        return entries.map(ResolutionEntry.init)
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
