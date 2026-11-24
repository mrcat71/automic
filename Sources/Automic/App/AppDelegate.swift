import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenu.build()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--settings-snapshot"), arguments.indices.contains(index + 1) {
            DeviceSwitcher.shared.loadSample()
            SettingsSnapshotRunner.run(outputDirectory: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
            return
        }
        DeviceSwitcher.shared.start()
        statusItem = StatusItemController()
        Updater.shared.start()
        Log.app.notice("Automic started")
    }

    /// Opening Automic again from Finder or Spotlight shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowController.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Updater.shared.checkForUpdates()
    }

    @objc func showHelp(_ sender: Any?) {
        if let url = URL(string: "https://github.com/mrcat71/automic") {
            NSWorkspace.shared.open(url)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return Updater.shared.canCheckForUpdates
        }
        return true
    }
}
