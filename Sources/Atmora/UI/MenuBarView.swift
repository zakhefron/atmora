import AppKit
import SwiftUI
import AtmoraCore

/// The menu-bar popover: the whole product in one view. Header, a now-playing
/// card with prev / play / next, the full mix, and quit. Styled to feel like a
/// small Apple Music panel — soft glass cards, a living artwork thumbnail, and
/// restrained typography.
struct MenuBarView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var isVisible = false

    private var playback: PlaybackController { coordinator.playback }
    private var preferences: PreferencesStore { coordinator.preferences }

    private var selected: SoundEnvironment { playback.selectedEnvironment }
    private var tint: Color { Color.environmentAccent(playback.selectedEnvironmentID) }

    private var environmentPosition: String {
        let ids = coordinator.catalog.environments.map(\.id)
        let index = ids.firstIndex(of: playback.selectedEnvironmentID) ?? 0
        return String(format: "%02d / %02d", index + 1, ids.count)
    }

    var body: some View {
        VStack(spacing: 10) {
            header

            nowPlayingSection

            atmosphereSection

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 336)
        .background(QuietBackground(accent: tint))
        .background(Palette.backgroundTop)
        .preferredColorScheme(preferences.theme.colorScheme)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BrandLockup(symbolSize: 17, fontSize: 12.5)

            Spacer(minLength: 8)

            statusPill
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .frame(height: 26)
    }

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 6) {
            if playback.isPlaying && preferences.soundEnabled {
                EqualizerBars(tint: tint)
            } else {
                Circle()
                    .fill(preferences.soundEnabled ? Palette.tertiaryText.opacity(0.45) : Palette.tertiaryText.opacity(0.28))
                    .frame(width: 5, height: 5)
            }

            Text(headerStatus)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surface.opacity(0.6))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.border.opacity(0.55), lineWidth: 1)
        )
    }

    private var headerStatus: String {
        guard preferences.soundEnabled else { return "SOUND OFF" }
        if playback.isPlaying { return "PLAYING" }
        return "READY"
    }

    // MARK: - Now playing

    private var nowPlayingSection: some View {
        MenuCard(padding: 14) {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 13) {
                    ambiencePreview

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(selected.name)
                                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(environmentPosition)
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(Palette.tertiaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.border.opacity(0.45)))
                        }

                        Text(selected.tagline)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(playback.isPlaying && preferences.soundEnabled ? tint : Palette.tertiaryText.opacity(0.4))
                                .frame(width: 4, height: 4)
                            Text(playbackStatusText)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.tertiaryText)
                                .lineLimit(1)
                        }
                        .padding(.top, 1)
                    }

                    Spacer(minLength: 0)
                }

                controlsRow
            }
        }
    }

    private var playbackStatusText: String {
        guard preferences.soundEnabled else { return "Sound off" }
        if playback.isPlaying { return "Playing through this Mac" }
        return "Ready"
    }

    @ViewBuilder
    private var ambiencePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.backgroundBottom)

            SceneArtwork(
                environment: selected.id,
                animated: isVisible,
                playing: playback.isPlaying
            )
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(playback.isSelectedEnvironmentAvailable ? 1 : 0.42)
        }
        .frame(width: 78, height: 78)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.30)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
        }
        .shadow(color: tint.opacity(0.38), radius: 12, x: 0, y: 4)
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            MenuCircleButton(
                systemName: "chevron.backward",
                tint: tint,
                size: 36,
                help: "Previous ambience (⌘[)",
                shortcut: "[",
                action: { playback.selectPrevious() }
            )

            Spacer(minLength: 0)

            PlayButton(
                isPlaying: playback.isPlaying,
                isEnabled: playback.isSelectedEnvironmentAvailable && preferences.soundEnabled,
                size: 46
            ) {
                playback.togglePlayback()
            }

            Spacer(minLength: 0)

            MenuCircleButton(
                systemName: "chevron.forward",
                tint: tint,
                size: 36,
                help: "Next ambience (⌘])",
                shortcut: "]",
                action: { playback.selectNext() }
            )
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Atmosphere

    private var atmosphereSection: some View {
        let effects = preferences.desktopEffects
        return MenuCard(padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Atmosphere")

                // Sound, with the mix it controls directly beneath it.
                VStack(alignment: .leading, spacing: 9) {
                    MenuAtmosphereToggle(
                        symbol: "speaker.wave.2.fill",
                        title: "Sound",
                        isOn: preferences.soundEnabled,
                        tint: tint
                    ) { coordinator.setSoundEnabled($0) }

                    if preferences.soundEnabled {
                        mixBlock
                    }
                }

                Hairline()

                // Desktop, with the effects it controls directly beneath it.
                VStack(alignment: .leading, spacing: 9) {
                    MenuAtmosphereToggle(
                        symbol: "display",
                        title: "Desktop",
                        isOn: preferences.desktopMode == .livingDesktop,
                        tint: tint
                    ) { coordinator.setDesktopEnabled($0) }

                    if preferences.desktopMode == .livingDesktop {
                        effectsBlock(effects)
                    } else {
                        Text("Your desktop stays exactly as it is.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
            }
        }
    }

    private var mixBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("Mix")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)

                Spacer(minLength: 4)

                Text("\(selected.layers.count) layers")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Palette.tertiaryText.opacity(0.8))

                if playback.lastMixSavedAt != nil {
                    Label("Saved", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityLabel("Mix saved")
                }

                Button("Save") { playback.saveMix() }
                    .buttonStyle(PillButtonStyle())
                    .controlSize(.mini)
                    .help("Save this mix for \(selected.name)")

                Button("Reset") { playback.resetMix() }
                    .buttonStyle(PillButtonStyle())
                    .controlSize(.mini)
                    .help("Restore the ambience preset levels")
            }

            VolumeRow(value: playback.masterVolume, tint: tint) { newValue in
                playback.setMasterVolume(newValue)
            }

            Hairline()

            ForEach(selected.layers) { layer in
                let setting = playback.layerSettings.first { $0.id == layer.id }
                    ?? LayerSetting(id: layer.id, level: layer.defaultLevel)
                MenuLayerRow(
                    layer: layer,
                    setting: setting,
                    tint: tint,
                    onChange: { playback.setLayerLevel(layer.id, level: $0) },
                    onMute: { playback.toggleMute(layer.id) }
                )
            }
        }
    }

    private func effectsBlock(_ effects: DesktopEffects) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
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

            HStack(spacing: 8) {
                Text("Effect intensity")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiaryText)

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
                .controlSize(.mini)
                .accessibilityLabel("Desktop effect intensity")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Original soundscapes. Nothing leaves this Mac.")
                .font(.system(size: 9))
                .foregroundStyle(Palette.tertiaryText.opacity(0.9))

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit Atmora")
            .accessibilityLabel("Quit Atmora")
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
    }
}

// MARK: - Card surface

/// A soft, elevated card used by both sections. The faint top highlight keeps
/// the surface from reading as flat grey in dark mode.
private struct MenuCard<Content: View>: View {
    var padding: CGFloat
    var content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.055), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Controls

private struct MenuCircleButton: View {
    let systemName: String
    let tint: Color
    let size: CGFloat
    let help: String
    var shortcut: KeyEquivalent? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Palette.surfaceElevated : Palette.surface.opacity(0.55))
                Circle()
                    .strokeBorder(Palette.border.opacity(0.55), lineWidth: 1)
                Circle()
                    .fill(tint.opacity(isHovered ? 0.18 : 0.09))
                    .scaleEffect(0.60)
                Image(systemName: systemName)
                    .font(.system(size: size * 0.31, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .help(help)
    }
}

/// Three tiny bars that pulse while sound is playing. It reads as "alive" at a
/// glance without adding noise to the layout.
private struct EqualizerBars: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            bars(at: timeline.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityHidden(true)
    }

    private func bars(at time: TimeInterval) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            bar(index: 0, time: time)
            bar(index: 1, time: time)
            bar(index: 2, time: time)
        }
        .frame(height: 8, alignment: .bottom)
    }

    private func bar(index: Int, time: TimeInterval) -> some View {
        let speed = 2.4 + Double(index) * 0.7
        let phase = Double(index) * 1.3
        let height = CGFloat(3.0 + 4.5 * abs(sin(time * speed + phase)))
        return Capsule(style: .continuous)
            .fill(tint)
            .frame(width: 2, height: height)
    }
}

/// A two-state row used in the popover's Atmosphere card.
private struct MenuAtmosphereToggle: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let tint: Color
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                Spacer(minLength: 2)
                Circle()
                    .fill(isOn ? tint : Palette.tertiaryText.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isOn ? Palette.secondaryText : Palette.tertiaryText)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? tint.opacity(0.10) : Palette.surface.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? tint.opacity(0.22) : Palette.border.opacity(0.55), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Layer row

/// One layer of the active mix, styled like the app's LayerRow but compact.
private struct MenuLayerRow: View {
    let layer: SoundLayer
    let setting: LayerSetting
    let tint: Color
    var onChange: (Double) -> Void
    var onMute: () -> Void

    private var percent: Int { Int((setting.effectiveLevel * 100).rounded()) }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: layer.symbolName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(setting.isMuted ? Palette.tertiaryText.opacity(0.6) : tint)
                    .frame(width: 16)

                Text(layer.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(setting.isMuted ? Palette.tertiaryText.opacity(0.6) : Palette.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(setting.isMuted ? "Muted" : "\(percent)%")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText)
                    .accessibilityHidden(true)

                Button(action: onMute) {
                    Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.1")
                        .font(.system(size: 9.5))
                        .foregroundStyle(setting.isMuted ? tint : Palette.tertiaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(setting.isMuted ? "Unmute \(layer.name)" : "Mute \(layer.name)")
                .help(setting.isMuted ? "Unmute \(layer.name)" : "Mute \(layer.name)")
            }

            Slider(
                value: Binding(get: { setting.level }, set: { onChange($0) }),
                in: 0...1
            )
            .tint(tint)
            .controlSize(.mini)
            .disabled(setting.isMuted)
            .accessibilityLabel("\(layer.name) level")
            .accessibilityValue("\(percent) percent")
            .accessibilityHint(layer.detail)
        }
        .padding(.vertical, 2)
        .opacity(setting.isMuted ? 0.75 : 1)
    }
}
