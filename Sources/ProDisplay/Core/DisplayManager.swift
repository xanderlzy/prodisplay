import AppKit
import CoreGraphics

/// A display shown in the menu's display picker.
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
}

enum DisplayManager {
    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func builtinDisplayID() -> CGDirectDisplayID? {
        onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Names seen earlier; a display mirroring another has no NSScreen to ask.
    nonisolated(unsafe) private static var names: [CGDirectDisplayID: String] = [:]

    /// Displays whose resolution can be changed, built-in first: the online ones, minus
    /// ProDisplay's own virtual displays and displays that just mirror another (their mode
    /// follows the display they mirror). A display mirroring one of ProDisplay's virtual
    /// displays is showing a custom resolution, so it stays.
    static func configurableDisplays() -> [DisplayInfo] {
        // Online, not active: a display mirroring another drops out of the active list.
        onlineDisplays()
            .filter { id in
                guard !CustomResolutionService.isVirtual(id) else { return false }
                let master = CGDisplayMirrorsDisplay(id)
                return master == kCGNullDirectDisplay || CustomResolutionService.isVirtual(master)
            }
            .map { id in
                let builtin = CGDisplayIsBuiltin(id) != 0
                if let name = screen(for: id)?.localizedName { names[id] = name }
                let name = builtin ? "Built-in Display" : (names[id] ?? "External Display")
                return DisplayInfo(id: id, name: name, isBuiltin: builtin)
            }
            .sorted { $0.isBuiltin && !$1.isBuiltin }
    }

    /// A key that stays the same for a monitor across reconnects and restarts.
    static func persistentKey(for id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    static func isOnline(_ id: CGDirectDisplayID) -> Bool {
        onlineDisplays().contains(id)
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}
