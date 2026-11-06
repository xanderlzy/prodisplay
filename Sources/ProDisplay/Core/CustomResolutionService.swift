import CGVirtualDisplayPrivate
import CoreGraphics
import Foundation

/// A user-made "looks like" size for one display.
struct CustomResolution: Codable, Hashable, Identifiable {
    let width: Int
    let height: Int
    let hiDPI: Bool

    var id: String { "\(width)x\(height)\(hiDPI ? "@2x" : "")" }
    var pixelWidth: Int { hiDPI ? width * 2 : width }
    var pixelHeight: Int { hiDPI ? height * 2 : height }
}

enum CustomResolutionError: LocalizedError {
    case createFailed, notOnline, modeMissing, mirrorFailed

    var errorDescription: String? {
        switch self {
        case .createFailed: "macOS couldn't create that custom resolution."
        case .notOnline: "The custom resolution didn't come online."
        case .modeMissing: "macOS didn't offer that size."
        case .mirrorFailed: "Couldn't show the custom resolution on the display."
        }
    }
}

/// Custom resolutions. Apple Silicon Macs only accept the modes a display reports, so each
/// custom size is drawn on a private virtual display that the real display then mirrors.
/// The mirror is set for this session only: if ProDisplay quits or crashes, the virtual
/// display disappears and macOS goes back to the display's normal mode.
@MainActor
final class CustomResolutionService {
    nonisolated static let vendorID: UInt32 = 0x5044 // "PD"

    private struct Session {
        let virtual: CGVirtualDisplay
        let resolution: CustomResolution
    }

    /// Keyed by the physical display showing the custom resolution.
    private var sessions: [CGDirectDisplayID: Session] = [:]

    func active(on display: CGDirectDisplayID) -> CustomResolution? {
        sessions[display]?.resolution
    }

    nonisolated static func isVirtual(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == vendorID
    }

    func enable(_ resolution: CustomResolution, on physical: CGDirectDisplayID, refreshRate: Double) async throws {
        if sessions[physical] != nil { await disable(on: physical) }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "ProDisplay Custom"
        descriptor.maxPixelsWide = UInt32(resolution.pixelWidth)
        descriptor.maxPixelsHigh = UInt32(resolution.pixelHeight)
        descriptor.sizeInMillimeters = CGDisplayScreenSize(physical)
        descriptor.vendorID = Self.vendorID
        descriptor.productID = 0x0002
        descriptor.serialNum = physical
        // sRGB primaries and D65 white point, as a typical monitor reports them.
        descriptor.redPrimary = CGPoint(x: 0.640, y: 0.330)
        descriptor.greenPrimary = CGPoint(x: 0.300, y: 0.600)
        descriptor.bluePrimary = CGPoint(x: 0.150, y: 0.060)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)

        let virtual = CGVirtualDisplay(descriptor: descriptor)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = resolution.hiDPI ? 1 : 0
        let rates = Set([max(refreshRate, 60), 60]).sorted(by: >)
        // A HiDPI size needs both its pixel size and its point size listed; macOS then
        // offers the point size at 2×.
        var sizes = [(resolution.pixelWidth, resolution.pixelHeight)]
        if resolution.hiDPI { sizes.append((resolution.width, resolution.height)) }
        settings.modes = sizes.flatMap { size in
            rates.map { CGVirtualDisplayMode(width: UInt(size.0), height: UInt(size.1), refreshRate: $0) }
        }
        guard virtual.apply(settings) else { throw CustomResolutionError.createFailed }

        let id = virtual.displayID
        do {
            try await waitUntilOnline(id)
            // The virtual display's modes can show up a moment after it comes online.
            var attempt = 0
            while true {
                do {
                    try mirror(physical, to: id, resolution: resolution)
                    break
                } catch CustomResolutionError.modeMissing where attempt < 20 {
                    attempt += 1
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            sessions[physical] = Session(virtual: virtual, resolution: resolution)
            Log.brightness.notice("Custom resolution \(resolution.id) on display \(physical)")
        } catch {
            Log.brightness.notice("Custom resolution \(resolution.id) failed: \(error.localizedDescription)")
            throw error // releasing `virtual` removes it
        }
    }

    func disable(on physical: CGDirectDisplayID) async {
        guard sessions[physical] != nil else { return }
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success {
            CGConfigureDisplayMirrorOfDisplay(config, physical, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        try? await Task.sleep(for: .milliseconds(300))
        sessions[physical] = nil // releasing the virtual display removes it
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Drops sessions whose physical display was unplugged.
    func prune(keeping online: [CGDirectDisplayID]) {
        for id in sessions.keys where !online.contains(id) { sessions[id] = nil }
    }

    private func waitUntilOnline(_ id: CGDirectDisplayID) async throws {
        for _ in 0..<40 {
            if DisplayManager.isOnline(id) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CustomResolutionError.notOnline
    }

    private func mirror(_ physical: CGDirectDisplayID, to virtual: CGDirectDisplayID, resolution: CustomResolution) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { throw CustomResolutionError.mirrorFailed }

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(virtual, options) as? [CGDisplayMode] ?? []
        if let mode = modes
            .filter({ $0.width == resolution.width && $0.pixelWidth == resolution.pixelWidth })
            .max(by: { $0.refreshRate < $1.refreshRate }) {
            CGConfigureDisplayWithDisplayMode(config, virtual, mode, nil)
        } else if let index = SkyLightModes.index(on: virtual, width: resolution.width,
                                                  height: resolution.height, density: resolution.hiDPI ? 2 : 1) {
            SkyLightModes.configure(config, display: virtual, index: index)
        } else {
            CGCancelDisplayConfiguration(config)
            throw CustomResolutionError.modeMissing
        }
        CGConfigureDisplayMirrorOfDisplay(config, physical, virtual)
        // .forSession: nothing persists if the app quits or crashes.
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            CGCancelDisplayConfiguration(config)
            throw CustomResolutionError.mirrorFailed
        }
    }
}

/// Display modes through private SkyLight calls, for when CoreGraphics doesn't list them.
private enum SkyLightModes {
    private typealias CountFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias DescribeFn = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutablePointer<PDDisplayModeDescription>, Int32) -> Void
    private typealias ConfigureFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> CGError

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let count: CountFn? = symbol("CGSGetNumberOfDisplayModes")
    private static let describe: DescribeFn? = symbol("CGSGetDisplayModeDescriptionOfLength")
    private static let configureMode: ConfigureFn? = symbol("CGSConfigureDisplayMode")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// The fastest mode with this point size and pixel density.
    static func index(on display: CGDirectDisplayID, width: Int, height: Int, density: Float) -> Int32? {
        guard let count, let describe, configureMode != nil else { return nil }
        var total: Int32 = 0
        count(display, &total)
        var best: (index: Int32, freq: UInt16)?
        for i in 0..<max(total, 0) {
            var mode = PDDisplayModeDescription()
            describe(display, i, &mode, Int32(MemoryLayout<PDDisplayModeDescription>.size))
            let m = mode.derived
            guard Int(m.width) == width, Int(m.height) == height, abs(m.density - density) < 0.01 else { continue }
            if best.map({ m.freq > $0.freq }) ?? true { best = (i, m.freq) }
        }
        return best?.index
    }

    static func configure(_ config: CGDisplayConfigRef?, display: CGDirectDisplayID, index: Int32) {
        _ = configureMode?(config, display, index)
    }
}
