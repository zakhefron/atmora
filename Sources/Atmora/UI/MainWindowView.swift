import AppKit
import SwiftUI
import AtmoraCore

/// The primary Atmora window: one large environment canvas, a calm selection
/// rail, and a mixer that exposes every layer. The window itself is owned by
/// AppKit; this view only supplies content.
struct MainWindowView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startupNoticeDismissed = false

    private var playback: PlaybackController { coordinator.playback }
    private var preferences: PreferencesStore { coordinator.preferences }
    private var tint: Color { Color.environmentAccent(playback.selectedEnvironmentID) }
    private var isCompact: Bool { preferences.density == .compact }
    private var animationsActive: Bool {
        preferences.animationEnabled && !reduceMotion && coordinator.isWindowVisible
    }

    var body: some View {
        ZStack {
            QuietBackground(accent: tint)

            VStack(spacing: 0) {
                header
                if let notice = bannerMessage {
                    NoticeBanner(
                        message: notice.text,
                        actionTitle: notice.canRetry ? "Try Again" : nil,
                        action: notice.canRetry ? { playback.retryAfterFailure() } : nil,
                        onDismiss: notice.isStartup ? { startupNoticeDismissed = true } : { playback.clearError() }
                    )
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                content
                footer
            }
        }
        .frame(minWidth: 800, minHeight: 640)
        .preferredColorScheme(preferences.theme.colorScheme)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: playback.errorMessage)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: playback.selectedEnvironmentID)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            BrandLockup(symbolSize: 22, fontSize: 14)

            Spacer(minLength: 12)

            statusBadgeInHeader
        }
        .padding(.leading, 24)
        .padding(.trailing, 22)
        .frame(height: isCompact ? 48 : 56)
    }

    @ViewBuilder
    private var statusBadgeInHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(playback.isPlaying && preferences.soundEnabled ? tint : Color.white.opacity(0.45))
                .frame(width: 5, height: 5)
            Text(statusText)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.36)))
    }

    // MARK: - Main content

    private var content: some View {
        HStack(alignment: .top, spacing: isCompact ? 14 : 18) {
            hero
            rail
                .frame(width: isCompact ? 280 : 306)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            SceneArtwork(
                environment: playback.selectedEnvironmentID,
                animated: animationsActive,
                playing: playback.isPlaying
            )
            .id(playback.selectedEnvironmentID)
            .transition(.opacity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.10), .black.opacity(0.62)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Quiet index and status, top corners.
            VStack {
                HStack(alignment: .top) {
                    Text(environmentIndex)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.34)))

                    Spacer()

                    statusBadge
                }
                Spacer()
            }
            .padding(18)

            VStack(alignment: .leading, spacing: 8) {
                Text(playback.selectedEnvironment.name)
                    .font(.system(size: isCompact ? 27 : 33, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.30), radius: 10, y: 2)

                Text(playback.selectedEnvironment.tagline)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
                    .frame(maxWidth: 420, alignment: .leading)

                HStack(spacing: 12) {
                    PlayButton(
                        isPlaying: playback.isPlaying,
                        isEnabled: playback.isSelectedEnvironmentAvailable && preferences.soundEnabled,
                        size: isCompact ? 46 : 52
                    ) {
                        playback.togglePlayback()
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playButtonTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(layerSummary)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.top, 5)
            }
            .padding(isCompact ? 20 : 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(playback.selectedEnvironment.name) artwork")
    }

    private var rail: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 14) {
                ambienceSection
                atmosphereSection
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.automatic)
    }

    private var ambienceSection: some View {
        SurfaceCard(padding: isCompact ? 10 : 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "Ambience")
                    Spacer()
                    Text("⌘1–\(coordinator.catalog.environments.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryText)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 2) {
                    ForEach(coordinator.catalog.environments) { environment in
                        EnvironmentRow(
                            environment: environment,
                            isSelected: environment.id == playback.selectedEnvironmentID,
                            isAvailable: coordinator.assetReport.available.contains(environment.id),
                            isPlaying: playback.isPlaying,
                            tint: Color.environmentAccent(environment.id),
                            compact: isCompact
                        ) {
                            playback.select(environment.id)
                        }
                    }
                }
            }
        }
    }

    private var atmosphereSection: some View {
        let effects = preferences.desktopEffects
        return SurfaceCard(padding: isCompact ? 12 : 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Atmosphere")

                // Sound, with the mix it controls directly beneath it.
                VStack(alignment: .leading, spacing: 11) {
                    AtmosphereToggleRow(
                        symbol: "speaker.wave.2.fill",
                        title: "Sound",
                        detail: preferences.soundEnabled ? "Playing through this Mac" : "Silent until you turn sound on",
                        isOn: preferences.soundEnabled,
                        tint: tint
                    ) { coordinator.setSoundEnabled($0) }

                    if preferences.soundEnabled {
                        mixBlock
                    }
                }

                Hairline()

                // Desktop, with the effects it controls directly beneath it.
                VStack(alignment: .leading, spacing: 11) {
                    AtmosphereToggleRow(
                        symbol: "display",
                        title: "Desktop",
                        detail: preferences.desktopMode == .livingDesktop ? "Living Desktop preview active" : "Your desktop stays exactly as it is",
                        isOn: preferences.desktopMode.usesDesktopWallpaper,
                        tint: tint
                    ) { coordinator.setDesktopEnabled($0) }

                    if preferences.desktopMode == .livingDesktop {
                        Text("Shape the atmosphere beyond the window.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.tertiaryText)

                        effectsBlock(effects)
                    }

                    if let issue = coordinator.desktop.lastError {
                        Text(issue)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var mixBlock: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("Mix")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                if playback.lastMixSavedAt != nil {
                    Label("Saved", systemImage: "checkmark")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(tint)
                        .transition(.opacity)
                }
                Button("Save") {
                    playback.saveMix()
                }
                .buttonStyle(PillButtonStyle())
                .help("Save this mix for \(playback.selectedEnvironment.name)")

                Button("Reset") {
                    playback.resetMix()
                }
                .buttonStyle(PillButtonStyle())
                .help("Restore the ambience preset levels")
            }

            VolumeRow(value: playback.masterVolume, tint: tint) { newValue in
                playback.setMasterVolume(newValue)
            }

            Hairline()

            ForEach(playback.selectedEnvironment.layers) { layer in
                if let setting = setting(for: layer.id) {
                    LayerRow(
                        layer: layer,
                        setting: setting,
                        tint: tint,
                        onChange: { playback.setLayerLevel(layer.id, level: $0) },
                        onMute: { playback.toggleMute(layer.id) }
                    )
                }
            }

            if let issue = playback.selectedEnvironmentIssue {
                Text(issue)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func effectsBlock(_ effects: DesktopEffects) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                EffectChip(
                    symbol: "waveform.path",
                    title: "Motion",
                    isOn: effects.motionEnabled,
                    tint: tint
                ) { value in
                    var updated = effects
                    updated.motionEnabled = value
                    coordinator.setDesktopEffects(updated)
                }

                EffectChip(
                    symbol: "sun.max.fill",
                    title: "Bloom",
                    isOn: effects.bloomEnabled,
                    tint: tint
                ) { value in
                    var updated = effects
                    updated.bloomEnabled = value
                    coordinator.setDesktopEffects(updated)
                }

                EffectChip(
                    symbol: "sparkles",
                    title: "Particles",
                    isOn: effects.particlesEnabled,
                    tint: tint
                ) { value in
                    var updated = effects
                    updated.particlesEnabled = value
                    coordinator.setDesktopEffects(updated)
                }
            }

            HStack(spacing: 10) {
                Text("Intensity")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)

                Slider(
                    value: Binding(
                        get: { preferences.desktopEffects.intensity },
                        set: { value in
                            var updated = preferences.desktopEffects
                            updated.intensity = value
                            coordinator.setDesktopEffects(updated)
                        }
                    ),
                    in: 0...1
                )
                .tint(tint)
                .controlSize(.small)
                .accessibilityLabel("Desktop effect intensity")

                Text("\(Int((preferences.desktopEffects.intensity * 100).rounded()))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 26, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Original soundscapes. Nothing leaves this Mac.")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiaryText)

            Spacer()

            Text("⌘P to play")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Palette.tertiaryText.opacity(0.8))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .frame(height: isCompact ? 26 : 32)
    }

    // MARK: - Derived state

    private var environmentIndex: String {
        let ids = coordinator.catalog.environments.map(\.id)
        guard let index = ids.firstIndex(of: playback.selectedEnvironmentID) else {
            return String(format: "01 / %02d", ids.count)
        }
        return String(format: "%02d / %02d", index + 1, ids.count)
    }

    private var playButtonTitle: String {
        if !playback.isSelectedEnvironmentAvailable { return "Unavailable" }
        if !preferences.soundEnabled { return "Sound is off" }
        switch playback.state {
        case .playing: return "Pause \(playback.selectedEnvironment.name)"
        case .paused: return "Resume \(playback.selectedEnvironment.name)"
        case .idle: return "Play \(playback.selectedEnvironment.name)"
        }
    }

    private var layerSummary: String {
        let layers = playback.selectedEnvironment.layers
        let audible = playback.layerSettings.filter { !$0.isMuted && $0.level > 0.01 }.count
        let names = layers.map(\.name).joined(separator: " · ")
        return audible == 0 ? "All layers muted" : names
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(playback.isPlaying && preferences.soundEnabled ? tint : Color.white.opacity(0.45))
                .frame(width: 5, height: 5)
            Text(statusText)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.36)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }

    private var statusText: String {
        if !preferences.soundEnabled { return "SOUND OFF" }
        switch playback.state {
        case .playing: return "PLAYING"
        case .paused: return "PAUSED"
        case .idle:
            return playback.isSelectedEnvironmentAvailable ? "READY" : "MISSING AUDIO"
        }
    }

    private func setting(for layerID: String) -> LayerSetting? {
        playback.layerSettings.first { $0.id == layerID }
    }

    private struct BannerMessage {
        var text: String
        var canRetry: Bool
        var isStartup: Bool
    }

    private var bannerMessage: BannerMessage? {
        if let error = playback.errorMessage {
            return BannerMessage(text: error, canRetry: playback.isSelectedEnvironmentAvailable, isStartup: false)
        }
        if let issue = coordinator.startupNotice, !startupNoticeDismissed {
            return BannerMessage(text: issue, canRetry: false, isStartup: true)
        }
        return nil
    }
}
