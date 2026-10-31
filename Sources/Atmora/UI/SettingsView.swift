import AppKit
import SwiftUI
import AtmoraCore

/// A compact, scrollable preferences window, opened from the standard
/// **Atmora › Settings…** menu item. It is deliberately separate from the
/// main window and the menu-bar popover.
struct SettingsPanel: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var notificationsOn = false
    @State private var notificationBusy = false
    @State private var notificationError: String?
    @State private var launchMessage: String?
    @State private var didLoad = false

    private var preferences: PreferencesStore { coordinator.preferences }
    private var playback: PlaybackController { coordinator.playback }
    private var tint: Color { Color.environmentAccent(playback.selectedEnvironmentID) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    atmosphereSection
                    focusSection
                    soundSection
                    appearanceSection
                    generalSection
                    aboutSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 380)
        .frame(maxHeight: 580)
        .background(Palette.backgroundTop)
        .onAppear(perform: load)
        .task {
            await coordinator.notifications.refreshStatus()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text("Atmora, tuned to your room")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(
                Circle().fill(Palette.surface)
            )
            .overlay(
                Circle().strokeBorder(Palette.border, lineWidth: 1)
            )
            .help("Close settings")
            .accessibilityLabel("Close settings")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .overlay(alignment: .bottom) {
            Hairline()
        }
    }

    // MARK: - Atmosphere

    private var atmosphereSection: some View {
        SettingsGroup(title: "Atmosphere") {
            AtmosphereToggleRow(
                symbol: "speaker.wave.2.fill",
                title: "Sound",
                detail: preferences.soundEnabled ? "Playing through this Mac" : "Silent until you turn sound on",
                isOn: preferences.soundEnabled,
                tint: tint
            ) { coordinator.setSoundEnabled($0) }

            Hairline()

            AtmosphereToggleRow(
                symbol: "display",
                title: "Desktop",
                detail: preferences.desktopMode == .livingDesktop ? "Living Desktop preview active" : "Your desktop stays as it is",
                isOn: preferences.desktopMode.usesDesktopWallpaper,
                tint: tint
            ) { coordinator.setDesktopEnabled($0) }

            if let error = coordinator.desktop.lastError {
                SettingsWarning(text: error)
            }
        }
    }

    // MARK: - Focus

    private var focusSection: some View {
        SettingsGroup(title: "Focus") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Session length")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondaryText)
                    Text("Drag to choose, then start from the Playback menu.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiaryText)
                }
                Spacer(minLength: 6)
                Text(FocusDuration.summary(for: preferences.lastFocusMinutes))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            FocusDurationSlider(
                minutes: preferences.lastFocusMinutes,
                tint: tint,
                compact: true
            ) { preferences.lastFocusMinutes = $0 }

            Hairline()

            Toggle("Fade sound out when a session ends", isOn: prefBinding(\.stopAudioWhenTimerEnds))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            Toggle("Notify me when a session ends", isOn: notificationsBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))
                .disabled(notificationBusy)

            if notificationBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Updating notification permission…")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiaryText)
                }
            } else if let notificationError {
                SettingsNote(text: notificationError)
            } else {
                SettingsNote(text: "Permission: \(coordinator.notifications.authorizationStatus). Notifications stay on this Mac.")
            }
        }
    }

    // MARK: - Sound

    private var soundSection: some View {
        SettingsGroup(title: "Sound") {
            LabeledSlider(
                title: "Fade in",
                value: prefBinding(\.fadeInSeconds),
                range: 0...8,
                step: 0.1,
                valueText: String(format: "%.1f s", preferences.fadeInSeconds)
            )
            LabeledSlider(
                title: "Fade out",
                value: prefBinding(\.fadeOutSeconds),
                range: 0...8,
                step: 0.1,
                valueText: String(format: "%.1f s", preferences.fadeOutSeconds)
            )
            SettingsNote(text: "Fades apply when you start, pause, or switch rooms. Turning Sound off fades out immediately and leaves playback paused.")

            Hairline()

            AssetStatusRow(
                title: audioStatusTitle,
                detail: audioStatusDetail,
                isOK: coordinator.assetReport.isComplete
            )
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsGroup(title: "Appearance") {
            Picker("Theme", selection: prefBinding(\.theme)) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Picker("Density", selection: prefBinding(\.density)) {
                ForEach(DensityPreference.allCases, id: \.self) { density in
                    Text(density.label).tag(density)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Toggle("Ambient artwork motion", isOn: prefBinding(\.animationEnabled))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            if reduceMotion {
                SettingsNote(text: "Reduce Motion is enabled in System Settings, so artwork stays still regardless of this setting.")
            } else {
                SettingsNote(text: "Every room animates subtly while sound is playing. Motion stops when audio is paused.")
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        SettingsGroup(title: "General") {
            HStack(spacing: 10) {
                Text("When Atmora opens")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondaryText)
                Spacer(minLength: 6)
                Picker("When Atmora opens", selection: prefBinding(\.launchBehavior)) {
                    ForEach(LaunchBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.label).tag(behavior)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 190)
            }

            Toggle("Open at login", isOn: launchAtLoginBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            if let issue = launchMessage ?? coordinator.launchAtLoginIssue {
                SettingsNote(text: issue)
            }

            Hairline()

            Toggle("Enable the global shortcut", isOn: prefBinding(\.shortcutEnabled))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show or hide Atmora")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondaryText)
                    Text("Default is \(KeyCombo.default.display)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiaryText)
                }
                Spacer(minLength: 6)
                ShortcutRecorder()
            }

            if let issue = coordinator.shortcutIssue {
                SettingsNote(text: issue)
            }

            HStack {
                Spacer()
                Button("Restore Default Shortcut") {
                    preferences.shortcut = .default
                }
                .controlSize(.mini)
                .disabled(preferences.shortcut == KeyCombo.default)
            }

            Hairline()

            Toggle("Restore the last room", isOn: prefBinding(\.restoreLastEnvironment))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            Toggle("Resume playback when Atmora opens", isOn: prefBinding(\.resumePlaybackOnLaunch))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11.5))

            SettingsNote(text: "Playback never starts on launch unless you enable this, and never while Sound is off.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsGroup(title: "About") {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text("Atmora")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .tracking(0.6)
                    Text("Version \(AppResources.versionDescription)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryText)
                    Text("\(coordinator.catalog.environments.count) rooms · \(layerCount) layers · no network")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiaryText)
                }

                Spacer(minLength: 0)
            }

            SettingsNote(text: "Every sound is generated procedurally for Atmora. No accounts, analytics, telemetry, or network requests. Preferences and mixes stay on this Mac.")
        }
    }

    private var icon: some View {
        Group {
            if let image = AppResources.applicationIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Palette.backgroundBottom, Palette.backgroundTop],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    BrandMark(size: 30)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Bindings

    private func prefBinding<T>(_ keyPath: ReferenceWritableKeyPath<PreferencesStore, T>) -> Binding<T> {
        Binding(
            get: { coordinator.preferences[keyPath: keyPath] },
            set: { coordinator.preferences[keyPath: keyPath] = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { coordinator.preferences.launchAtLogin },
            set: { newValue in
                launchMessage = coordinator.setLaunchAtLogin(newValue)
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsOn },
            set: { newValue in
                notificationsOn = newValue
                notificationBusy = true
                notificationError = nil
                Task {
                    let issue = await coordinator.setNotificationsEnabled(newValue)
                    notificationBusy = false
                    if let issue {
                        notificationError = issue
                        notificationsOn = false
                    }
                }
            }
        )
    }


    // MARK: - Lifecycle

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        notificationsOn = preferences.notificationsEnabled
    }

    // MARK: - Helpers

    private var layerCount: Int {
        coordinator.catalog.environments.reduce(0) { $0 + $1.layers.count }
    }

    private var audioStatusTitle: String {
        coordinator.assetReport.isComplete ? "Audio library ready" : "Some audio is unavailable"
    }

    private var audioStatusDetail: String {
        let available = coordinator.assetReport.available.count
        if coordinator.assetReport.isComplete {
            return "All \(layerCount) layers across \(coordinator.catalog.environments.count) rooms are present and readable."
        }
        return "\(available) of \(coordinator.catalog.environments.count) rooms have complete audio. Affected rooms are marked in the main window."
    }
}

// MARK: - Reusable panel pieces

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
        }
    }
}

private struct SettingsWarning: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10))
            .foregroundStyle(Palette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Palette.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 6)
            Slider(value: $value, in: range, step: step)
                .frame(width: 160)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Palette.tertiaryText)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
