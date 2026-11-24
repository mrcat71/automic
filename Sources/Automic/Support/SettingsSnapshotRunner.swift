import AppKit
import SwiftUI

/// Offline UI check: renders every settings pane with sample devices in light and dark
/// appearances to PNGs and quits. Starts neither CoreAudio observation nor Sparkle, and saves
/// nothing. The release smoke test runs it.
enum SettingsSnapshotRunner {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func run(outputDirectory: URL) {
        Task {
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                try await capture(into: outputDirectory)
                NSApp.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("settings-snapshot failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    private static func capture(into directory: URL) async throws {
        SettingsWindowController.shared.show()
        guard let window = SettingsWindowController.shared.window,
              let tabs = window.contentViewController as? NSTabViewController
        else {
            throw Failure(errorDescription: "Settings window has no tab controller")
        }
        tabs.transitionOptions = []
        let panel = NSWindow(contentViewController: NSHostingController(rootView: PanelView()))
        panel.styleMask = [.borderless]
        panel.isReleasedWhenClosed = false
        for style in [NSAppearance.Name.aqua, .darkAqua] {
            let mode = style == .aqua ? "light" : "dark"
            window.appearance = NSAppearance(named: style)
            for index in tabs.tabViewItems.indices {
                tabs.selectedTabViewItemIndex = index
                try await snapshot(window, named: "\(mode)-\(tabs.tabViewItems[index].label.lowercased())", into: directory)
            }
            panel.appearance = NSAppearance(named: style)
            panel.orderFront(nil)
            try await snapshot(panel, named: "\(mode)-panel", into: directory)
            panel.orderOut(nil)
        }
        try writeMenuBarIcon(to: directory.appendingPathComponent("menu-bar-icon.png"))
    }

    /// The template glyph at 4x, black on clear.
    private static func writeMenuBarIcon(to url: URL) throws {
        let icon = MenuBarIcon.image()
        let scale: CGFloat = 4
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(icon.size.width * scale), pixelsHigh: Int(icon.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw Failure(errorDescription: "Could not allocate the menu bar icon bitmap")
        }
        bitmap.size = icon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(origin: .zero, size: icon.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(errorDescription: "Could not encode the menu bar icon")
        }
        try data.write(to: url)
        print("wrote \(url.path)")
    }

    private static func snapshot(_ window: NSWindow, named name: String, into directory: URL) async throws {
        try await Task.sleep(for: .milliseconds(200))
        guard let view = window.contentView else { throw Failure(errorDescription: "No content view for \(name)") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(errorDescription: "Could not render \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(errorDescription: "Could not encode \(name)")
        }
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("wrote \(url.path)")
    }
}
