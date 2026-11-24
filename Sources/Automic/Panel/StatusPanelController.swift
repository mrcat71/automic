import AppKit
import SwiftUI

/// A borderless panel that can take the keyboard (Escape closes it).
final class StatusPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

/// Shows `PanelView` under the menu bar icon and closes it on a click elsewhere, Escape, or a
/// second click on the icon.
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let panel: StatusPanel
    private let hosting: NSHostingController<PanelView>
    private weak var anchor: NSStatusBarButton?
    private var clickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        hosting = NSHostingController(rootView: PanelView())
        super.init()
        hosting.rootView = PanelView(
            onOpenSettings: { [weak self] in
                self?.close()
                SettingsWindowController.shared.show()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
    }

    func toggle(from button: NSStatusBarButton) {
        if isVisible {
            close()
        } else {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton) {
        anchor = button
        position()
        // Active, so the switch and sliders draw in their active colors.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        anchor?.highlight(false)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Under the icon, centered on it, kept on the icon's screen.
    private func position() {
        guard let button = anchor, let window = button.window else { return }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = hosting.view.fittingSize
        var x = icon.midX - size.width / 2
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(x: x, y: icon.minY - 6 - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Content grew or shrank (the disconnected devices toggle): keep the top under the icon.
    func windowDidResize(_ notification: Notification) {
        guard panel.isVisible, let button = anchor, let window = button.window else { return }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let top = icon.minY - 6
        if abs(panel.frame.maxY - top) > 0.5 {
            panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
        }
    }
}
