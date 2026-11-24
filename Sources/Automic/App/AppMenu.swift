import AppKit

/// Main menu, visible while the settings window is open: Command-W, Command-Q and the text
/// editing shortcuts need it.
enum AppMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Automic", [
            item("About Automic", #selector(AppDelegate.showAbout(_:))),
            item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Hide Automic", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Automic", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        let window = submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        let help = submenu("Help", [item("Automic on GitHub", #selector(AppDelegate.showHelp(_:)))])
        main.addItem(help)
        NSApp.helpMenu = help.submenu
        return main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

/// Target of a closure-based menu item.
final class MenuActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) { handler() }
}

extension NSMenuItem {
    /// Menu item that runs `handler`; the item keeps its target alive.
    static func action(_ title: String, keyEquivalent: String = "", handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuActionTarget(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.run(_:)), keyEquivalent: keyEquivalent)
        item.target = target
        item.representedObject = target
        return item
    }

    func with(symbol: String) -> Self {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return self
    }
}
