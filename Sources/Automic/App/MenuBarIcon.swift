import AppKit

/// The menu bar glyph: the app icon's microphone with two sound waves, drawn as a template so it
/// follows the menu bar's appearance. A plain headphones symbol was too easy to mistake for
/// other audio items.
enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Microphone head, cradle, stem and base.
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 7.5, width: 5, height: 8.5), xRadius: 2.5, yRadius: 2.5).fill()
            let stand = NSBezierPath()
            stand.lineWidth = 1.5
            stand.lineCapStyle = .round
            stand.appendArc(withCenter: NSPoint(x: 6, y: 10.5), radius: 4.25, startAngle: 180, endAngle: 360)
            stand.move(to: NSPoint(x: 6, y: 6.25))
            stand.line(to: NSPoint(x: 6, y: 3))
            stand.move(to: NSPoint(x: 3.5, y: 2.75))
            stand.line(to: NSPoint(x: 8.5, y: 2.75))
            stand.stroke()

            // Sound waves: the output side.
            for radius in [CGFloat(3.25), 6] {
                let wave = NSBezierPath()
                wave.lineWidth = 1.5
                wave.lineCapStyle = .round
                wave.appendArc(withCenter: NSPoint(x: 10.5, y: 11.5), radius: radius, startAngle: -45, endAngle: 45)
                wave.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Automic"
        return image
    }
}
