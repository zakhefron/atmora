import AppKit
import Observation
import SwiftUI
import AtmoraCore

@MainActor
@Observable
final class LivingDesktopModel {
    var environment: EnvironmentID
    var intensity: DesktopAnimationIntensity
    var effects: DesktopEffects

    init(environment: EnvironmentID, intensity: DesktopAnimationIntensity, effects: DesktopEffects) {
        self.environment = environment
        self.intensity = intensity
        self.effects = effects
    }
}

/// A window-based preview of the animated atmosphere. It is placed at the
/// desktop window level, behind normal windows, and ignores the mouse. It is
/// deliberately labelled a preview in Settings: public macOS APIs cannot set a
/// true animated system wallpaper.
@MainActor
final class LivingDesktopPreviewController {
    private var windows: [String: NSWindow] = [:]
    private var model: LivingDesktopModel?

    var isVisible: Bool { !windows.isEmpty }

    func show(
        screens: [(screen: NSScreen, id: String)],
        environment: EnvironmentID,
        intensity: DesktopAnimationIntensity,
        effects: DesktopEffects
    ) {
        hide()
        let model = LivingDesktopModel(environment: environment, intensity: intensity, effects: effects)
        self.model = model

        for entry in screens {
            let window = NSWindow(
                contentRect: entry.screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: entry.screen
            )
            // One point above the desktop level keeps the atmosphere above the
            // desktop picture but below Finder's desktop icons, which live 20
            // levels higher.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.contentView = NSHostingView(rootView: LivingDesktopView(model: model))
            window.orderFrontRegardless()
            windows[entry.id] = window
        }
    }

    func update(environment: EnvironmentID, intensity: DesktopAnimationIntensity, effects: DesktopEffects) {
        model?.environment = environment
        model?.intensity = intensity
        model?.effects = effects
    }

    func hide() {
        for window in windows.values {
            window.orderOut(nil)
        }
        windows.removeAll()
        model = nil
    }
}

struct LivingDesktopView: View {
    let model: LivingDesktopModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            // Draw the atmosphere at a 16:9 composition and fill the display,
            // cropping rather than stretching it on unusual aspect ratios. The
            // Canvas scenes are designed for a wide, cinematic frame.
            let scale = max(geometry.size.width / 16.0, geometry.size.height / 9.0)
            let sceneSize = CGSize(width: 16 * scale, height: 9 * scale)

            ZStack {
                Color.black

                SceneArtwork(
                    environment: model.environment,
                    animated: !reduceMotion && model.effects.motionEnabled,
                    playing: false,
                    alwaysAnimates: model.effects.motionEnabled,
                    frameInterval: model.intensity.frameInterval,
                    motionOpacity: model.intensity.motionOpacity,
                    effects: model.effects
                )
                .frame(width: sceneSize.width, height: sceneSize.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Keep desktop icons and text legible without dimming the
                // atmosphere into something muddy.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.20)],
                    center: .center,
                    startRadius: 160,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.72
                )
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.black.opacity(0.10), .clear, .black.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
