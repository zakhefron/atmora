import AppKit
import SwiftUI
import AtmoraCore

/// Records a global shortcut without requiring Accessibility access. It listens
/// only while the button is armed, converts the event to Atmora's persisted
/// `KeyCombo`, and immediately re-registers the Carbon hot key.
struct ShortcutRecorder: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var messageIsError = false

    private var combo: KeyCombo? { coordinator.preferences.shortcut }
    private var isEnabled: Bool { coordinator.preferences.shortcutEnabled }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button {
                toggleRecording()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isRecording ? Palette.accent : Palette.tertiaryText)

                    Text(displayText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(isRecording ? Palette.accent : Palette.secondaryText)
                        .frame(minWidth: 40)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isRecording ? Palette.accent.opacity(0.10) : Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isRecording ? Palette.accent.opacity(0.45) : Palette.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
            .help(isEnabled ? "Click, then press a new key combination. Escape cancels." : "Enable the global shortcut first.")
            .accessibilityLabel("Global shortcut, \(combo?.display ?? "not set")")
            .accessibilityHint("Click, then press a new key combination")

            if let message {
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(messageIsError ? Palette.accent : Palette.tertiaryText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var displayText: String {
        if isRecording { return "Press keys…" }
        return combo?.display ?? "Not set"
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard monitor == nil else { return }
        isRecording = true
        message = "Press a combination with ⌘, ⌥, or ⌃. Escape cancels."
        messageIsError = false

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async {
                handle(event)
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == 53 { // Escape
            stopRecording()
            message = nil
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = KeyCombo.Modifiers()
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        guard modifiers.hasCommandLikeModifier else {
            message = "Add ⌘, ⌥, or ⌃ so the shortcut does not capture ordinary typing."
            messageIsError = true
            return
        }

        guard let key = Self.keyName(for: event) else {
            message = "That key cannot be used. Try a letter, number, or function key."
            messageIsError = true
            return
        }

        let candidate = KeyCombo(keyCode: event.keyCode, key: key, modifiers: modifiers)
        stopRecording()
        apply(candidate)
    }

    private func apply(_ candidate: KeyCombo) {
        guard candidate.isValid else {
            message = "That combination is not valid."
            messageIsError = true
            return
        }

        let previous = coordinator.preferences.shortcut ?? .default
        coordinator.preferences.shortcut = candidate

        if let issue = coordinator.shortcutIssue {
            coordinator.preferences.shortcut = previous
            message = issue
            messageIsError = true
        } else {
            message = "Shortcut updated to \(candidate.display)."
            messageIsError = false
        }
    }

    private static func keyName(for event: NSEvent) -> String? {
        if let special = specialKeys[event.keyCode] {
            return special
        }

        guard let characters = event.characters(byApplyingModifiers: []),
              let first = characters.first else {
            return nil
        }

        let value = String(first)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value.uppercased()
    }

    private static let specialKeys: [UInt16: String] = [
        36: "Return",
        76: "Enter",
        48: "Tab",
        49: "Space",
        51: "Delete",
        117: "Forward Delete",
        115: "Home",
        119: "End",
        116: "Page Up",
        121: "Page Down",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12"
    ]
}
