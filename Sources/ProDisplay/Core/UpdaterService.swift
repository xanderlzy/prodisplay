import AppKit
import Sparkle

/// Self-updates via Sparkle. The feed URL and public signing key are in Info.plist;
/// `./build.sh release` produces the signed zip and appcast.xml for each GitHub release.
@MainActor
final class UpdaterService: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        // A menu bar app isn't frontmost; bring Sparkle's window to the front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // A menu bar app has no Dock icon to badge, so let Sparkle show scheduled
    // update alerts gently instead of interrupting.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
