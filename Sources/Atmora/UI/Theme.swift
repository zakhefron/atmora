import AppKit
import SwiftUI
import AtmoraCore

enum Palette {
    static let accent = Color.adaptive(
        light: NSColor(srgbRed: 0.55, green: 0.36, blue: 0.18, alpha: 1),
        dark: NSColor(srgbRed: 0.84, green: 0.65, blue: 0.44, alpha: 1)
    )

    static let backgroundTop = Color.adaptive(
        light: NSColor(srgbRed: 0.965, green: 0.952, blue: 0.930, alpha: 1),
        dark: NSColor(srgbRed: 0.050, green: 0.057, blue: 0.067, alpha: 1)
    )

    static let backgroundBottom = Color.adaptive(
        light: NSColor(srgbRed: 0.925, green: 0.906, blue: 0.874, alpha: 1),
        dark: NSColor(srgbRed: 0.082, green: 0.087, blue: 0.100, alpha: 1)
    )

    static let surface = Color.adaptive(
        light: NSColor(srgbRed: 1.0, green: 0.996, blue: 0.985, alpha: 0.78),
        dark: NSColor(srgbRed: 0.106, green: 0.116, blue: 0.133, alpha: 0.86)
    )

    static let surfaceOpaque = Color.adaptive(
        light: NSColor(srgbRed: 0.976, green: 0.965, blue: 0.947, alpha: 1),
        dark: NSColor(srgbRed: 0.102, green: 0.110, blue: 0.125, alpha: 1)
    )

    static let surfaceElevated = Color.adaptive(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.92),
        dark: NSColor(srgbRed: 0.137, green: 0.148, blue: 0.167, alpha: 0.98)
    )

    static let border = Color.adaptive(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.085)
    )

    static let strongBorder = Color.adaptive(
        light: NSColor.black.withAlphaComponent(0.16),
        dark: NSColor.white.withAlphaComponent(0.18)
    )

    static let secondaryText = Color.adaptive(
        light: NSColor(srgbRed: 0.34, green: 0.32, blue: 0.30, alpha: 1),
        dark: NSColor(srgbRed: 0.69, green: 0.69, blue: 0.70, alpha: 1)
    )

    static let tertiaryText = Color.adaptive(
        light: NSColor(srgbRed: 0.46, green: 0.44, blue: 0.41, alpha: 1),
        dark: NSColor(srgbRed: 0.52, green: 0.52, blue: 0.54, alpha: 1)
    )

    static let warning = Color.adaptive(
        light: NSColor(srgbRed: 0.62, green: 0.36, blue: 0.06, alpha: 1),
        dark: NSColor(srgbRed: 0.93, green: 0.68, blue: 0.35, alpha: 1)
    )

    static let shadow = Color.black.opacity(0.38)
}

struct EnvironmentTint {
    let accent: Color
    let glow: Color

    static func forEnvironment(_ id: EnvironmentID) -> EnvironmentTint {
        switch id {
        case .rainyCabin:
            return EnvironmentTint(
                accent: .adaptive(light: NSColor(srgbRed: 0.56, green: 0.34, blue: 0.16, alpha: 1), dark: NSColor(srgbRed: 0.90, green: 0.65, blue: 0.37, alpha: 1)),
                glow: Color(red: 0.93, green: 0.62, blue: 0.29)
            )
        case .train:
            return EnvironmentTint(
                accent: .adaptive(light: NSColor(srgbRed: 0.28, green: 0.37, blue: 0.46, alpha: 1), dark: NSColor(srgbRed: 0.65, green: 0.76, blue: 0.87, alpha: 1)),
                glow: Color(red: 0.53, green: 0.69, blue: 0.84)
            )
        case .sakuraNight:
            return EnvironmentTint(
                accent: .adaptive(light: NSColor(srgbRed: 0.60, green: 0.30, blue: 0.38, alpha: 1), dark: NSColor(srgbRed: 0.96, green: 0.68, blue: 0.74, alpha: 1)),
                glow: Color(red: 0.96, green: 0.56, blue: 0.66)
            )
        case .cloudLibrary:
            return EnvironmentTint(
                accent: .adaptive(light: NSColor(srgbRed: 0.47, green: 0.35, blue: 0.30, alpha: 1), dark: NSColor(srgbRed: 0.88, green: 0.72, blue: 0.58, alpha: 1)),
                glow: Color(red: 0.92, green: 0.68, blue: 0.48)
            )
        case .sunsetDrive:
            return EnvironmentTint(
                accent: .adaptive(light: NSColor(srgbRed: 0.60, green: 0.35, blue: 0.18, alpha: 1), dark: NSColor(srgbRed: 0.98, green: 0.70, blue: 0.46, alpha: 1)),
                glow: Color(red: 1.0, green: 0.58, blue: 0.34)
            )
        case .seasideRecords:
            return EnvironmentTint(
                accent: .adaptive(light: NSColor(srgbRed: 0.28, green: 0.42, blue: 0.47, alpha: 1), dark: NSColor(srgbRed: 0.65, green: 0.83, blue: 0.87, alpha: 1)),
                glow: Color(red: 0.47, green: 0.75, blue: 0.80)
            )
        }
    }
}

extension Color {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }

    static func environmentAccent(_ id: EnvironmentID) -> Color {
        EnvironmentTint.forEnvironment(id).accent
    }
}

extension ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

struct QuietBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.backgroundTop, Palette.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.10), accent.opacity(0.025), .clear],
                center: UnitPoint(x: 0.86, y: 0.02),
                startRadius: 0,
                endRadius: 720
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.06)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = Palette.tertiaryText

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, isActive: isActive, size: size)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isActive: Bool
        let size: CGFloat
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isActive ? Palette.accent : Palette.secondaryText)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(isActive ? Palette.accent.opacity(0.12) : (isHovered ? Palette.border.opacity(0.9) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(isActive ? Palette.accent.opacity(0.25) : .clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct PillButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(prominent ? Color.white : Palette.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(prominent ? Palette.accent.opacity(configuration.isPressed ? 0.75 : 1) : Palette.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(prominent ? .clear : Palette.border, lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        }
    }
}
