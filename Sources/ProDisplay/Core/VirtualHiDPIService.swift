import CGVirtualDisplayPrivate
import CoreGraphics
import Foundation

struct CustomSize: Codable, Hashable, Identifiable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }
}

enum HiDPIError: LocalizedError {
    case createFailed, notOnline, modeMissing, mirrorFailed

    var errorDescription: String? {
        switch self {
        case .createFailed: "Couldn't create the scaled display."
        case .notOnline: "The scaled display didn't come online."
        case .modeMissing: "macOS didn't offer that HiDPI size."
        case .mirrorFailed: "Couldn't mirror the built-in display."
        }
    }
}

/// Custom HiDPI "looks like" sizes: a private virtual display renders at the chosen
/// size with 2× backing pixels, and the built-in panel mirrors it.
@MainActor
final class VirtualHiDPIService {
    private var virtualDisplay: CGVirtualDisplay?
    private(set) var activeSize: CustomSize?

    func enable(_ size: CustomSize, builtin: CGDirectDisplayID) async throws {
        if activeSize != nil { await disable(builtin: builtin) }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "ProDisplay \(size.label)"
        descriptor.maxPixelsWide = UInt32(size.width * 2)
        descriptor.maxPixelsHigh = UInt32(size.height * 2)
        descriptor.sizeInMillimeters = CGDisplayScreenSize(builtin)
        descriptor.vendorID = 0x5044 // "PD"
        descriptor.productID = 0x0001
        descriptor.serialNum = UInt32(size.width)

        let display = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // Both point and pixel sizes, so the HiDPI mode is offered either way macOS interprets them.
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 120),
            CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 60),
            CGVirtualDisplayMode(width: UInt(size.width * 2), height: UInt(size.height * 2), refreshRate: 60),
        ]
        guard display.apply(settings) else { throw HiDPIError.createFailed }

        let id = display.displayID
        virtualDisplay = display

        do {
            try await waitUntilOnline(id)
            try configure(virtual: id, size: size, builtin: builtin)
            activeSize = size
        } catch {
            virtualDisplay = nil
            throw error
        }
    }

    func disable(builtin: CGDirectDisplayID) async {
        guard virtualDisplay != nil else { return }
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success {
            CGConfigureDisplayMirrorOfDisplay(config, builtin, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        try? await Task.sleep(for: .milliseconds(300))
        virtualDisplay = nil // releasing the object removes the display
        activeSize = nil
    }

    private func waitUntilOnline(_ id: CGDirectDisplayID) async throws {
        for _ in 0..<40 {
            if DisplayManager.isOnline(id) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HiDPIError.notOnline
    }

    private func configure(virtual id: CGDirectDisplayID, size: CustomSize, builtin: CGDirectDisplayID) throws {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        guard let mode = modes
            .filter({ $0.width == size.width && $0.pixelWidth == size.width * 2 })
            .max(by: { $0.refreshRate < $1.refreshRate })
        else { throw HiDPIError.modeMissing }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { throw HiDPIError.mirrorFailed }
        CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        CGConfigureDisplayMirrorOfDisplay(config, builtin, id)
        // .forSession: nothing persists if the app quits or crashes.
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            CGCancelDisplayConfiguration(config)
            throw HiDPIError.mirrorFailed
        }
    }
}
