import AppKit
import AQICore

@MainActor
enum StatusRenderer {
    static func image(text: String, band: AQIBand?, height: CGFloat = 22) -> NSImage {
        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let font = (band?.rawValue ?? 0) >= AQIBand.unhealthy.rawValue
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask) : baseFont
        let title = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: band?.nsColor ?? NSColor.secondaryLabelColor
        ])
        let textSize = title.size()
        let size = NSSize(width: ceil(textSize.width) + 2, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            title.draw(at: NSPoint(x: 1, y: floor((height - textSize.height) / 2)))
            return true
        }
        // AppKit may recolor status button titles. A non-template image preserves
        // the AQI colors, while NSFont.menuBarFont keeps the native typography.
        image.isTemplate = false
        image.accessibilityDescription = text
        return image
    }
}
