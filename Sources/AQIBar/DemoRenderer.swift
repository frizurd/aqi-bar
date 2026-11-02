import AppKit
import AQICore
import SwiftUI

/// Captures the real settings view using isolated, synthetic state.
/// No screen recording, personal preferences, or API requests are involved.
@MainActor
enum DemoRenderer {
    static func render(to directory: URL) throws {
        let suite = "AQIBar.demo.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let city = SavedLocation(name: "Jakarta, Indonesia", latitude: -6.2, longitude: 106.8)
        let searchStore = AQIStore(defaults: defaults, key: { "" })
        let search = LocationSearch(demoQuery: "Jakarta, Indonesia", demoResults: [city])
        let searchImage = try capture(SettingsView(store: searchStore, search: search, isDemo: true))
        try save(searchImage, to: directory.appendingPathComponent("choose-location.png"))

        let now = Date()
        let reading = AQIReading(value: 105, city: "Jakarta", country: "Indonesia", observedAt: now, fetchedAt: now)
        defaults.set(try JSONEncoder().encode(LocationSelection.fixed(city)), forKey: "location")
        defaults.set(try JSONEncoder().encode(CachedReading(selection: .fixed(city), reading: reading)), forKey: "reading")
        let readingStore = AQIStore(defaults: defaults, key: { "" })
        let readingImage = try capture(SettingsView(store: readingStore, isDemo: true))
        try save(readingImage, to: directory.appendingPathComponent("reading.png"))

        let size = NSSize(width: 1440, height: 1080)
        let demo = NSImage(size: size)
        demo.lockFocus()
        NSColor(srgbRed: 0.075, green: 0.08, blue: 0.10, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/AppIcon.png")
        if let logo = NSImage(contentsOf: resources) {
            logo.draw(in: NSRect(x: 68, y: 964, width: 86, height: 86))
        }
        text("AQI Bar", x: 170, y: 1010, size: 32, weight: .semibold)
        text("Pick a city. Read its AQI from the menu bar.", x: 170, y: 976, size: 19, color: .lightGray)

        text("1  Choose a location", x: 76, y: 902, size: 22, weight: .medium)
        text("2  Get the nearest city’s reading", x: 844, y: 902, size: 22, weight: .medium)
        drawWindow(searchImage, at: NSPoint(x: 76, y: 183))
        drawWindow(readingImage, at: NSPoint(x: 844, y: 183))

        text("3", x: 632, y: 710, size: 22, weight: .semibold)
        text("In your", x: 632, y: 678, size: 18, color: .lightGray)
        text("menu bar", x: 632, y: 650, size: 18, color: .lightGray)
        NSColor(white: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 624, y: 588, width: 156, height: 42), xRadius: 9, yRadius: 9).fill()
        drawStatus("AQI 105", band: .sensitive, at: NSPoint(x: 648, y: 594))
        text("macOS system font", x: 632, y: 552, size: 14, color: .lightGray)

        text("The color follows US AQI. Above 150, the label also becomes bold.", x: 76, y: 123, size: 20)
        for (index, band) in AQIBand.allCases.enumerated() {
            let value = [25, 75, 125, 175, 250, 350][index]
            let x = CGFloat(76 + index * 205)
            drawStatus("AQI \(value)", band: band, at: NSPoint(x: x, y: 72))
        }
        text("App views and menu bar labels rendered with sample data.", x: 76, y: 30, size: 13, color: .lightGray)
        demo.unlockFocus()
        try save(demo, to: directory.appendingPathComponent("demo.png"))
    }

    private static func capture(_ content: SettingsView) throws -> NSImage {
        let view = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 670),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 510, height: 670)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw AQIBarError.message("Couldn’t capture the demo settings view.")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func drawWindow(_ image: NSImage, at origin: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        let bounds = NSRect(origin: origin, size: NSSize(width: 510, height: 700))
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).addClip()
        NSColor(white: 0.92, alpha: 1).setFill()
        bounds.fill()
        image.draw(in: NSRect(origin: origin, size: NSSize(width: 510, height: 670)))
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: origin.x + 12 + CGFloat(index * 18), y: origin.y + 681, width: 11, height: 11)).fill()
        }
        text("AQI Bar Settings", x: origin.x + 193, y: origin.y + 679, size: 12, color: .darkGray)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                             weight: NSFont.Weight = .regular, color: NSColor = .white) {
        (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
        ])
    }

    private static func drawStatus(_ text: String, band: AQIBand, at point: NSPoint) {
        let image = StatusRenderer.image(text: text, band: band)
        // Enlarge uniformly for the demo; keep the actual font's proportions.
        image.draw(in: NSRect(origin: point, size: NSSize(width: image.size.width * 1.4, height: image.size.height * 1.4)))
    }

    private static func save(_ image: NSImage, to url: URL) throws {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AQIBarError.message("Couldn’t encode the demo image.")
        }
        try png.write(to: url)
    }
}
