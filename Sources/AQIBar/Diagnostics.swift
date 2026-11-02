import AppKit
import SwiftUI
import AQICore
import MapKit

@MainActor
enum Diagnostics {
    static func run(_ arguments: [String]) async throws {
        if let index = arguments.firstIndex(of: "--render-preview"), arguments.indices.contains(index + 1) {
            try renderPreview(to: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
            return
        }
        var selection = LocationSelection.automatic
        if let index = arguments.firstIndex(of: "--check-location"), arguments.indices.contains(index + 1) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = arguments[index + 1]
            request.resultTypes = .address
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { throw AQIBarError.message("No matching city found.") }
            selection = .fixed(SavedLocation(name: item.name ?? "Selected city",
                                            latitude: item.placemark.coordinate.latitude,
                                            longitude: item.placemark.coordinate.longitude))
            print("Location search: \(selection.title)")
        }
        let reading = try await IQAirClient().fetch(selection: selection, key: Credentials.activeKey)
        print("IQAir: \(reading.place) · US AQI \(reading.value) · \(reading.band.title)")
        print("Native menu font: \(NSFont.menuBarFont(ofSize: 0).fontName), \(NSFont.menuBarFont(ofSize: 0).pointSize) pt")
    }

    private static func renderPreview(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "AQIBar.preview.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = LocationSelection.fixed(SavedLocation(name: "Jakarta, Indonesia", latitude: -6.2, longitude: 106.8))
        defaults.set(try JSONEncoder().encode(selection), forKey: "location")
        let reading = AQIReading(value: 160, city: "Jakarta", country: "Indonesia", observedAt: Date(), fetchedAt: Date())
        defaults.set(try JSONEncoder().encode(CachedReading(selection: selection, reading: reading)), forKey: "reading")
        let store = AQIStore(defaults: defaults, key: { "" })
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let view = NSHostingView(rootView: SettingsView(store: store, isDemo: true)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 670), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: 510, height: 670)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw AQIBarError.message("Couldn’t render settings.") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("settings-\(name).png"))
        }
        let image = NSImage(size: NSSize(width: 610, height: 140))
        image.lockFocus()
        NSColor(white: 0.10, alpha: 1).setFill()
        NSRect(x: 0, y: 70, width: 610, height: 70).fill()
        NSColor(white: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 610, height: 70).fill()
        for (index, band) in AQIBand.allCases.enumerated() {
            let value = [25, 75, 125, 175, 250, 350][index]
            let rendered = StatusRenderer.image(text: "AQI \(value)", band: band)
            for y in [CGFloat(25), CGFloat(95)] {
                rendered.draw(at: NSPoint(x: CGFloat(index * 100 + 12), y: y), from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("menu-bar-colors.png"))
        try DemoRenderer.render(to: directory)
        print("Rendered settings and all six AQI menu bar colors to \(directory.path)")
    }
}
