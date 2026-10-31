import SwiftUI
import AtmoraCore

/// Focus timer controls, shown from the capsule in the window header. There is
/// one duration slider and one start button; presets and manual fields are gone.
struct FocusTimerPopover: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var notificationsOn = false
    @State private var notificationBusy = false
    @State private var notificationError: String?
    @State private var suppressNotificationBinding = false
    @State private var didLoad = false

    private var timer: FocusTimer { coordinator.focusTimer }
    private var preferences: PreferencesStore { coordinator.preferences }
    private var tint: Color { Color.environmentAccent(coordinator.playback.selectedEnvironmentID) }
    private var minutes: Int { preferences.lastFocusMinutes }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                SectionLabel(text: "Focus")
                Spacer()
                if timer.phase == .running || timer.phase == .paused {
                    Text(TimeFormatting.minutes(timer.duration))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            ring

            Group {
                switch timer.phase {
                case .idle:
                    setupControls
                case .finished:
                    finishedControls
                case .running, .paused:
                    activeControls
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: 9) {
                Toggle("Fade sound out when the session ends", isOn: stopAudioBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))

                Toggle("Notify me when the session ends", isOn: notificationsBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
                    .disabled(notificationBusy)

                if let notificationError {
                    Text(notificationError)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Palette.backgroundTop)
        .onAppear(perform: load)
        .onChange(of: notificationsOn) { _, newValue in
            guard didLoad else { return }
            applyNotifications(newValue)
        }
    }

    // MARK: - Sections

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Palette.border, lineWidth: 6)

            Circle()
                .trim(from: 0, to: timer.phase == .finished ? 1 : max(timer.progress, 0.0001))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: timer.progress)

            VStack(spacing: 3) {
                Text(timer.phase == .idle ? TimeFormatting.clock(minutes * 60) : TimeFormatting.clock(timer.remainingSeconds))
                    .font(.system(size: 31, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.primary)
                Text(ringSubtitle)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibilityText)
    }

    private var setupControls: some View {
        VStack(spacing: 12) {
            FocusDurationSlider(minutes: minutes, tint: tint) { value in
                preferences.lastFocusMinutes = value
            }

            Button {
                coordinator.startFocus(minutes: minutes)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Start \(FocusDuration.summary(for: minutes)) focus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule(style: .continuous).fill(tint))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a focus session and keeps the current soundscape")
        }
    }

    private var activeControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    if timer.phase == .running {
                        coordinator.pauseFocus()
                    } else {
                        coordinator.resumeFocus()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timer.phase == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 9.5))
                        Text(timer.phase == .running ? "Pause" : "Resume")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule(style: .continuous).fill(tint))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.cancelFocus()
                } label: {
                    Text("End Session")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule(style: .continuous).fill(Palette.surface))
                        .overlay(Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Stop the timer. Existing playback is not changed.")
            }

            Text(activeNote)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finishedControls: some View {
        VStack(spacing: 10) {
            Text("Your session is complete. Take your time returning.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                coordinator.dismissFinishedFocus()
            } label: {
                Text("Start Another")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule(style: .continuous).fill(tint))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bindings

    private var stopAudioBinding: Binding<Bool> {
        Binding(
            get: { preferences.stopAudioWhenTimerEnds },
            set: { preferences.stopAudioWhenTimerEnds = $0 }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsOn },
            set: { notificationsOn = $0 }
        )
    }

    // MARK: - Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        notificationsOn = preferences.notificationsEnabled
    }

    private func applyNotifications(_ enabled: Bool) {
        guard !suppressNotificationBinding else { return }
        notificationBusy = true
        Task {
            let issue = await coordinator.setNotificationsEnabled(enabled)
            notificationBusy = false
            if let issue {
                notificationError = issue
                if notificationsOn {
                    suppressNotificationBinding = true
                    notificationsOn = false
                    suppressNotificationBinding = false
                }
            } else {
                notificationError = nil
            }
        }
    }

    // MARK: - Labels

    private var ringSubtitle: String {
        switch timer.phase {
        case .idle: return "READY"
        case .running: return "IN FOCUS"
        case .paused: return "PAUSED"
        case .finished: return "COMPLETE"
        }
    }

    private var ringAccessibilityText: String {
        switch timer.phase {
        case .idle:
            return "Focus timer, \(FocusDuration.summary(for: minutes)), ready"
        case .running: return "Focus timer, \(TimeFormatting.clock(timer.remainingSeconds)) remaining"
        case .paused: return "Focus timer paused, \(TimeFormatting.clock(timer.remainingSeconds)) remaining"
        case .finished: return "Focus timer complete"
        }
    }

    private var activeNote: String {
        if preferences.stopAudioWhenTimerEnds {
            return "Sound fades out gently when the timer finishes."
        }
        return "Sound continues after the timer finishes."
    }
}
