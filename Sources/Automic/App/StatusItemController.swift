import AppKit
import Observation

/// The menu bar icon. A click opens the panel with the rankings and volumes.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = StatusPanelController()
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
        observeAutoSwitch()
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        panel.toggle(from: sender)
    }

    /// The panel and Settings can both turn switching off; the icon follows either.
    private func observeAutoSwitch() {
        withObservationTracking {
            _ = settings.autoSwitch
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observeAutoSwitch()
            }
        }
    }

    /// Dimmed while automatic switching is off.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = !settings.autoSwitch
        button.toolTip = settings.autoSwitch ? "Automic" : "Automic: automatic switching is off"
    }
}
