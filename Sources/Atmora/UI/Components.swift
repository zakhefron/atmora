import SwiftUI
import AtmoraCore

enum TimeFormatting {
    /// `m:ss` for short remainders, `h:mm:ss` only when genuinely needed.
    static func clock(_ seconds: Int) -> String {
        let value = max(seconds, 0)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let secs = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let value = max(seconds, 0) / 60
        let whole = Int(value)
        return "\(whole) min"
    }
}

extension EnvironmentID {
    var glyphName: String {
        switch self {
        case .rainyCabin: return "cloud.rain.fill"
        case .train: return "tram.fill"
        case .sakuraNight: return "leaf.fill"
        case .cloudLibrary: return "books.vertical.fill"
        case .sunsetDrive: return "car.fill"
        case .seasideRecords: return "opticaldisc.fill"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .rainyCabin: return "Rainy Cabin"
        case .train: return "Train Compartment"
        case .sakuraNight: return "Sakura Night"
        case .cloudLibrary: return "Cloud Library"
        case .sunsetDrive: return "Sunset Drive"
        case .seasideRecords: return "Seaside Records"
        }
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat
    var content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }
}

/// The large circular play control. It sits on artwork, so it uses a solid,
/// high-contrast face rather than a translucent one.
struct PlayButton: View {
    let isPlaying: Bool
    var isEnabled: Bool = true
    var size: CGFloat = 56
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isEnabled ? 0.95 : 0.4))
                Circle()
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(isEnabled ? 0.82 : 0.35))
                    .offset(x: isPlaying ? 0 : size * 0.025)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(isEnabled ? 0.28 : 0), radius: 14, x: 0, y: 5)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityHint(isEnabled ? "Starts or pauses the selected ambience" : "The selected ambience is unavailable")
        .help(isPlaying ? "Pause (⌘P)" : "Play (⌘P)")
    }
}

struct EnvironmentRow: View {
    let environment: SoundEnvironment
    let isSelected: Bool
    let isAvailable: Bool
    let isPlaying: Bool
    let tint: Color
    var compact: Bool = false
    var action: () -> Void

    private var rowHeight: CGFloat { compact ? 32 : 40 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: environment.id.glyphName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isSelected ? tint : Palette.tertiaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(environment.name)
                        .font(.system(size: compact ? 11.5 : 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Palette.secondaryText)
                    if !compact {
                        Text(environment.tagline)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if !isAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.tertiaryText)
                        .help("Audio files for this ambience are missing.")
                } else if isSelected && isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tint)
                } else if isSelected {
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.22) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(environment.name), \(environment.tagline)\(isAvailable ? "" : ", audio unavailable")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(isAvailable ? environment.description : "Audio files are missing for \(environment.name).")
    }
}

struct VolumeRow: View {
    let value: Double
    var tint: Color
    var showsLabel: Bool = true
    var onChange: (Double) -> Void

    private var symbol: String {
        if value <= 0.001 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.fill" }
        if value < 0.7 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onChange(value > 0.001 ? 0 : 0.68)
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(value > 0.001 ? "Mute" : "Unmute")
            .help(value > 0.001 ? "Mute master volume" : "Restore master volume")

            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: 0...1
            )
            .tint(tint)
            .controlSize(.small)
            .accessibilityLabel("Master volume")
            .accessibilityValue("\(Int((value * 100).rounded())) percent")

            if showsLabel {
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText)
                    .frame(width: 26, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct LayerRow: View {
    let layer: SoundLayer
    let setting: LayerSetting
    var tint: Color
    var onChange: (Double) -> Void
    var onMute: () -> Void

    private var percent: Int { Int((setting.effectiveLevel * 100).rounded()) }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: layer.symbolName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(setting.isMuted ? Palette.tertiaryText : tint.opacity(0.9))
                    .frame(width: 16)

                Text(layer.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(setting.isMuted ? Palette.tertiaryText : Palette.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(setting.isMuted ? "Muted" : "\(percent)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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
        .help(layer.detail)
        .opacity(setting.isMuted ? 0.72 : 1)
    }
}

struct TimerCapsule: View {
    let phase: FocusTimerPhase
    let remainingSeconds: Int
    let progress: Double
    var tint: Color
    var action: () -> Void

    private var label: String {
        switch phase {
        case .idle: return "Focus"
        case .running, .paused: return TimeFormatting.clock(remainingSeconds)
        case .finished: return "Complete"
        }
    }

    private var symbol: String {
        switch phase {
        case .idle: return "timer"
        case .running: return "timer.circle.fill"
        case .paused: return "pause.circle.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .medium))
                Text(label)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                if phase == .running {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .foregroundStyle(phase == .idle ? Palette.secondaryText : tint)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(phase == .idle ? Palette.surface : tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(phase == .idle ? Palette.border : tint.opacity(0.27), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .help("Focus timer")
    }

    private var accessibilityText: String {
        switch phase {
        case .idle: return "Focus timer"
        case .running: return "Focus timer running, \(TimeFormatting.clock(remainingSeconds)) remaining"
        case .paused: return "Focus timer paused, \(TimeFormatting.clock(remainingSeconds)) remaining"
        case .finished: return "Focus timer complete"
        }
    }
}

struct NoticeBanner: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.accent)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PillButtonStyle())
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

/// One slider, shared by the focus popover, the menu bar, and the in-window
/// settings panel. It always reflects the persisted duration and snaps to calm
/// five-minute steps.
struct FocusDurationSlider: View {
    let minutes: Int
    var tint: Color
    var compact: Bool = false
    var onChange: (Int) -> Void

    private var value: Binding<Double> {
        Binding(
            get: { Double(minutes) },
            set: { onChange(FocusDuration.clamp(Int($0.rounded()))) }
        )
    }

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            HStack(alignment: .firstTextBaseline) {
                if !compact {
                    Text("Duration")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer(minLength: 6)
                Text(FocusDuration.summary(for: minutes))
                    .font(.system(size: compact ? 10.5 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            Slider(
                value: value,
                in: Double(FocusDuration.minimumMinutes)...Double(FocusDuration.maximumMinutes),
                step: Double(FocusDuration.stepMinutes)
            )
            .tint(tint)
            .controlSize(compact ? .mini : .small)
            .accessibilityLabel("Focus duration")
            .accessibilityValue(FocusDuration.summary(for: minutes))
            .accessibilityHint("Choose a focus session from 5 minutes to 4 hours")

            HStack {
                Text("5 min")
                Spacer()
                Text("4 hours")
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.tertiaryText)
            .accessibilityHidden(true)
        }
    }
}

/// A quiet switch row for the Atmosphere card. The whole row is the hit target
/// so it behaves like a macOS preference row rather than a tiny control.
struct AtmosphereToggleRow: View {
    let symbol: String
    let title: String
    let detail: String
    let isOn: Bool
    var tint: Color
    var onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? tint : Palette.tertiaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                QuietSwitch(isOn: isOn, tint: tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(detail)
    }
}

/// A small, hand-drawn switch. It keeps its colour in inactive windows and in
/// off-screen snapshots, unlike the native switch, and matches the rest of the
/// app's drawn controls.
struct QuietSwitch: View {
    let isOn: Bool
    var tint: Color

    var body: some View {
        Capsule(style: .continuous)
            .fill(isOn ? tint : Palette.tertiaryText.opacity(0.28))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white.opacity(isOn ? 0.98 : 0.82))
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            }
            .animation(.easeOut(duration: 0.16), value: isOn)
            .accessibilityHidden(true)
    }
}

/// A compact on/off chip for the Living Desktop effect controls.
struct EffectChip: View {
    let symbol: String
    let title: String
    let isOn: Bool
    var tint: Color
    var onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(isOn ? tint : Palette.tertiaryText)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? tint.opacity(0.13) : Palette.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? tint.opacity(0.28) : Palette.border, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .help("\(title) \(isOn ? "on" : "off")")
    }
}

/// A small, honest availability badge used in the About and Audio settings.
struct AssetStatusRow: View {
    let title: String
    let detail: String
    let isOK: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(isOK ? Color.green : Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
