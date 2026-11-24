import AppKit
import Observation
@preconcurrency import Sparkle

/// In-app updates with Sparkle's standard windows. As a menu bar app, Automic opts into gentle
/// reminders: a scheduled update shows the Dock icon and comes to the front instead of opening
/// behind other apps.
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private(set) var isAvailable = false
    private(set) var canCheckForUpdates = false
    var checksAutomatically = false {
        didSet {
            if controller?.updater.automaticallyChecksForUpdates != checksAutomatically {
                controller?.updater.automaticallyChecksForUpdates = checksAutomatically
            }
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Only the packaged app has a feed; `swift run` builds have no Info.plist.
    func start() {
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        do {
            try controller.updater.start()
        } catch {
            Log.app.error("Updates could not start: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.controller = controller
        isAvailable = true
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.checksAutomatically = updater.automaticallyChecksForUpdates }
            },
        ]
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows every scheduled update itself; the callbacks below bring it to the front.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            DockPresence.shared.isShowingUpdate = true
            NSApp.activate()
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            DockPresence.shared.isShowingUpdate = false
        }
    }
}
