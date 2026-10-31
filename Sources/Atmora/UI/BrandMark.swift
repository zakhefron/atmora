import AppKit
import SwiftUI

/// Atmora's mark: the refreshed sound-wave symbol loaded from the bundled
/// mark image so it stays identical in the app header, the menu-bar popover,
/// and anywhere else BrandLockup appears. Sharp at every size because the
/// source is rendered at 512 px.
struct BrandMark: View {
    var size: CGFloat = 24
    var showsGlow: Bool = true  // kept for API compatibility; glow is baked into the mark image

    private static let markImage: NSImage = {
        if let url = Bundle.main.url(forResource: "AppMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: 24, height: 24))
    }()

    var body: some View {
        Image(nsImage: Self.markImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The horizontal lockup used in the window and menu-bar headers. The symbol is
/// the same geometry as the app icon; the wordmark uses the system serif face
/// with restrained tracking.
struct BrandLockup: View {
    var symbolSize: CGFloat = 22
    var fontSize: CGFloat = 14
    var showsGlow: Bool = true

    var body: some View {
        HStack(spacing: symbolSize * 0.42) {
            BrandMark(size: symbolSize, showsGlow: showsGlow)
            Text("Atmora")
                .font(.system(size: fontSize, weight: .medium, design: .serif))
                .tracking(fontSize * 0.055)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Atmora")
    }
}

enum MenuBarIcon {
    static func make() -> NSImage {
        // The refreshed app mark (twilight mountain + sun) drawn colourful,
        // non-template so it keeps its colours in both light and dark menu
        // bars. One high-res source is downscaled sharply to the 18 pt slot.
        let url = Bundle.main.url(forResource: "AppIconMenuBar", withExtension: "png")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = "Atmora"
        return image
    }
}
