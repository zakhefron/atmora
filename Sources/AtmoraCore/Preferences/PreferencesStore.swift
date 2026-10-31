import Foundation
import Observation

public enum ThemePreference: String, CaseIterable, Codable, Sendable {
    case system
    case dark
    case light

    public var label: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

public enum LaunchBehavior: String, CaseIterable, Codable, Sendable {
    case mainWindow
    case menuBar

    public var label: String {
        switch self {
        case .mainWindow: return "Show the main window"
        case .menuBar: return "Don't open the main window"
        }
    }
}

public enum DensityPreference: String, CaseIterable, Codable, Sendable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }
}

/// A keyboard combination that does not depend on AppKit so it can be
/// persisted and unit tested in the core module.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
        public static let all: Modifiers = [.control, .option, .shift, .command]

        /// Shortcuts without a command-like modifier would swallow ordinary typing.
        public var hasCommandLikeModifier: Bool {
            !intersection([.control, .option, .command]).isEmpty
        }

        public var display: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option) { result += "⌥" }
            if contains(.shift) { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    public var keyCode: UInt16
    public var key: String
    public var modifiers: Modifiers

    public init(keyCode: UInt16, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    public var display: String {
        modifiers.display + key.uppercased()
    }

    public var isValid: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && modifiers.hasCommandLikeModifier
    }

    /// ⌥⌘Q — rare in macOS, easy to reach, and does not collide with the
    /// system's log-out shortcut (⌃⌘Q).
    public static let `default` = KeyCombo(keyCode: 12, key: "Q", modifiers: [.option, .command])
}

public struct SavedMix: Codable, Equatable, Sendable {
    public var levels: [String: Double]
    public var muted: Set<String>
    public var savedAt: Date

    public init(levels: [String: Double], muted: Set<String> = [], savedAt: Date = Date()) {
        self.levels = levels
        self.muted = muted
        self.savedAt = savedAt
    }
}

public struct FocusTimerSnapshot: Codable, Equatable, Sendable {
    public var phase: FocusTimerPhase
    public var endDate: Date?
    public var remaining: TimeInterval
    public var duration: TimeInterval

    public init(phase: FocusTimerPhase, endDate: Date?, remaining: TimeInterval, duration: TimeInterval) {
        self.phase = phase
        self.endDate = endDate
        self.remaining = remaining
        self.duration = duration
    }
}

/// Everything Atmora persists. Decoding is deliberately forgiving: a missing
/// or malformed field falls back to a sensible default instead of losing all
/// preferences.
public struct AtmoraSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int = 1
    public var theme: ThemePreference = .system
    public var launchBehavior: LaunchBehavior = .mainWindow
    public var launchAtLogin: Bool = false
    public var shortcutEnabled: Bool = true
    public var shortcut: KeyCombo? = .default
    public var animationEnabled: Bool = true
    public var density: DensityPreference = .comfortable
    public var startupVolume: Double = 0.68
    public var lastMasterVolume: Double = 0.68
    public var fadeInSeconds: Double = 1.6
    public var fadeOutSeconds: Double = 1.2
    public var restoreLastEnvironment: Bool = true
    public var resumePlaybackOnLaunch: Bool = false
    public var lastEnvironment: EnvironmentID = .rainyCabin
    public var savedMixes: [String: SavedMix] = [:]
    public var notificationsEnabled: Bool = false
    public var stopAudioWhenTimerEnds: Bool = true
    public var lastFocusMinutes: Int = FocusDuration.defaultMinutes
    public var timerSnapshot: FocusTimerSnapshot?
    public var compactLayout: Bool = false

    /// Sound is the primary atmosphere switch. It is independent of the
    /// play/pause state so turning it back on never surprises anyone with
    /// sudden audio.
    public var soundEnabled: Bool = true

    // Desktop atmosphere. Both atmosphere switches are on by default: a fresh
    // install applies the Living Desktop animated preview for the selected
    // room, bringing the ambience beyond the window.
    public var desktopMode: DesktopAtmosphereMode = .livingDesktop
    public var desktopFollowsEnvironment: Bool = true
    public var desktopAnimationEnabled: Bool = true
    public var desktopAnimationIntensity: DesktopAnimationIntensity = .balanced
    public var desktopEffects: DesktopEffects = .standard
    public var desktopDisplay: DesktopDisplaySelection = .allDisplays
    public var desktopAppliedEnvironment: EnvironmentID?
    public var desktopOriginalWallpapers: [String: OriginalWallpaper] = [:]

    enum CodingKeys: String, CodingKey {
        case version, theme, launchBehavior, launchAtLogin, shortcutEnabled, shortcut
        case animationEnabled, density, startupVolume, lastMasterVolume
        case fadeInSeconds, fadeOutSeconds, restoreLastEnvironment, resumePlaybackOnLaunch
        case lastEnvironment, savedMixes, notificationsEnabled, stopAudioWhenTimerEnds
        case lastFocusMinutes, timerSnapshot, compactLayout, soundEnabled
        case desktopMode, desktopFollowsEnvironment, desktopAnimationEnabled
        case desktopAnimationIntensity, desktopDisplay, desktopAppliedEnvironment
        case desktopOriginalWallpapers, desktopEffects
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? Self.currentVersion
        theme = (try? container.decode(ThemePreference.self, forKey: .theme)) ?? .system
        launchBehavior = (try? container.decode(LaunchBehavior.self, forKey: .launchBehavior)) ?? .mainWindow
        launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        shortcutEnabled = (try? container.decode(Bool.self, forKey: .shortcutEnabled)) ?? true
        shortcut = (try? container.decodeIfPresent(KeyCombo.self, forKey: .shortcut)) ?? .default
        animationEnabled = (try? container.decode(Bool.self, forKey: .animationEnabled)) ?? true
        density = (try? container.decode(DensityPreference.self, forKey: .density)) ?? .comfortable
        startupVolume = (try? container.decode(Double.self, forKey: .startupVolume)) ?? 0.68
        lastMasterVolume = (try? container.decode(Double.self, forKey: .lastMasterVolume)) ?? 0.68
        fadeInSeconds = (try? container.decode(Double.self, forKey: .fadeInSeconds)) ?? 1.6
        fadeOutSeconds = (try? container.decode(Double.self, forKey: .fadeOutSeconds)) ?? 1.2
        restoreLastEnvironment = (try? container.decode(Bool.self, forKey: .restoreLastEnvironment)) ?? true
        resumePlaybackOnLaunch = (try? container.decode(Bool.self, forKey: .resumePlaybackOnLaunch)) ?? false
        lastEnvironment = (try? container.decode(EnvironmentID.self, forKey: .lastEnvironment)) ?? .rainyCabin
        savedMixes = (try? container.decode([String: SavedMix].self, forKey: .savedMixes)) ?? [:]
        notificationsEnabled = (try? container.decode(Bool.self, forKey: .notificationsEnabled)) ?? false
        stopAudioWhenTimerEnds = (try? container.decode(Bool.self, forKey: .stopAudioWhenTimerEnds)) ?? true
        lastFocusMinutes = FocusDuration.clamp((try? container.decode(Int.self, forKey: .lastFocusMinutes)) ?? FocusDuration.defaultMinutes)
        timerSnapshot = try? container.decodeIfPresent(FocusTimerSnapshot.self, forKey: .timerSnapshot)
        compactLayout = (try? container.decode(Bool.self, forKey: .compactLayout)) ?? false
        soundEnabled = (try? container.decode(Bool.self, forKey: .soundEnabled)) ?? true
        desktopMode = (try? container.decode(DesktopAtmosphereMode.self, forKey: .desktopMode)) ?? .livingDesktop
        desktopFollowsEnvironment = (try? container.decode(Bool.self, forKey: .desktopFollowsEnvironment)) ?? true
        desktopAnimationEnabled = (try? container.decode(Bool.self, forKey: .desktopAnimationEnabled)) ?? true
        desktopAnimationIntensity = (try? container.decode(DesktopAnimationIntensity.self, forKey: .desktopAnimationIntensity)) ?? .balanced
        desktopEffects = ((try? container.decode(DesktopEffects.self, forKey: .desktopEffects)) ?? .standard).normalized
        desktopDisplay = (try? container.decode(DesktopDisplaySelection.self, forKey: .desktopDisplay)) ?? .allDisplays
        desktopAppliedEnvironment = try? container.decodeIfPresent(EnvironmentID.self, forKey: .desktopAppliedEnvironment)
        desktopOriginalWallpapers = (try? container.decode([String: OriginalWallpaper].self, forKey: .desktopOriginalWallpapers)) ?? [:]
    }

    public mutating func normalize() {
        version = Self.currentVersion
        startupVolume = min(max(startupVolume, 0), 1)
        lastMasterVolume = min(max(lastMasterVolume, 0), 1)
        fadeInSeconds = min(max(fadeInSeconds, 0), 8)
        fadeOutSeconds = min(max(fadeOutSeconds, 0), 8)
        lastFocusMinutes = FocusDuration.clamp(lastFocusMinutes)
        desktopDisplay.normalize()
        desktopEffects = desktopEffects.normalized
        if !desktopMode.usesDesktopWallpaper {
            desktopAppliedEnvironment = nil
        }
        desktopOriginalWallpapers = desktopOriginalWallpapers.reduce(into: [:]) { result, entry in
            guard !entry.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result[entry.key] = entry.value
        }

        if let combo = shortcut {
            shortcut = combo.isValid ? combo : .default
        }
        if !shortcutEnabled {
            // Keep the stored combination so re-enabling is effortless.
        }
        savedMixes = savedMixes.reduce(into: [:]) { result, entry in
            let levels = entry.value.levels.mapValues { min(max($0, 0), 1) }
            result[entry.key] = SavedMix(
                levels: levels,
                muted: entry.value.muted,
                savedAt: entry.value.savedAt
            )
        }
    }
}

public enum PreferencesError: Error, Equatable {
    case unreadableData
}

@MainActor
@Observable
public final class PreferencesStore {
    public private(set) var settings: AtmoraSettings
    public private(set) var loadIssue: String?
    public private(set) var persistenceIssue: String?

    public var onThemeChanged: ((ThemePreference) -> Void)?
    public var onShortcutChanged: (() -> Void)?

    private let defaults: UserDefaults
    private let storageKey: String
    private var saveTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard, storageKey: String = "atmora.settings.v1") {
        self.defaults = defaults
        self.storageKey = storageKey

        if let data = defaults.data(forKey: storageKey) {
            do {
                var decoded = try JSONDecoder().decode(AtmoraSettings.self, from: data)
                decoded.normalize()
                self.settings = decoded
            } catch {
                self.settings = AtmoraSettings()
                self.loadIssue = "Atmora could not read its saved preferences, so it started with fresh settings."
                // Preserve the unreadable payload for diagnosis rather than silently deleting it.
                defaults.set(data, forKey: storageKey + ".unreadable")
            }
        } else {
            self.settings = AtmoraSettings()
        }
    }

    // MARK: - General

    public var theme: ThemePreference {
        get { settings.theme }
        set {
            guard settings.theme != newValue else { return }
            update { $0.theme = newValue }
            onThemeChanged?(newValue)
        }
    }

    public var launchBehavior: LaunchBehavior {
        get { settings.launchBehavior }
        set { update { $0.launchBehavior = newValue } }
    }

    public var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set { update { $0.launchAtLogin = newValue } }
    }

    public var shortcutEnabled: Bool {
        get { settings.shortcutEnabled }
        set {
            guard settings.shortcutEnabled != newValue else { return }
            update { $0.shortcutEnabled = newValue }
            onShortcutChanged?()
        }
    }

    public var shortcut: KeyCombo? {
        get { settings.shortcut }
        set {
            let sanitized = newValue?.isValid == true ? newValue : nil
            guard settings.shortcut != sanitized else { return }
            update { $0.shortcut = sanitized }
            onShortcutChanged?()
        }
    }

    // MARK: - Appearance

    public var animationEnabled: Bool {
        get { settings.animationEnabled }
        set { update { $0.animationEnabled = newValue } }
    }

    public var density: DensityPreference {
        get { settings.density }
        set { update { $0.density = newValue } }
    }

    public var compactLayout: Bool {
        get { settings.density == .compact }
        set { update { $0.density = newValue ? .compact : .comfortable } }
    }

    // MARK: - Audio

    public var startupVolume: Double {
        get { settings.startupVolume }
        set { update { $0.startupVolume = min(max(newValue, 0), 1) } }
    }

    public var lastMasterVolume: Double {
        get { settings.lastMasterVolume }
        set { update { $0.lastMasterVolume = min(max(newValue, 0), 1) } }
    }

    public var fadeInSeconds: Double {
        get { settings.fadeInSeconds }
        set { update { $0.fadeInSeconds = min(max(newValue, 0), 8) } }
    }

    public var fadeOutSeconds: Double {
        get { settings.fadeOutSeconds }
        set { update { $0.fadeOutSeconds = min(max(newValue, 0), 8) } }
    }

    public var restoreLastEnvironment: Bool {
        get { settings.restoreLastEnvironment }
        set { update { $0.restoreLastEnvironment = newValue } }
    }

    public var resumePlaybackOnLaunch: Bool {
        get { settings.resumePlaybackOnLaunch }
        set { update { $0.resumePlaybackOnLaunch = newValue } }
    }

    public var lastEnvironment: EnvironmentID {
        get { settings.lastEnvironment }
        set { update { $0.lastEnvironment = newValue } }
    }

    public var notificationsEnabled: Bool {
        get { settings.notificationsEnabled }
        set { update { $0.notificationsEnabled = newValue } }
    }

    public var stopAudioWhenTimerEnds: Bool {
        get { settings.stopAudioWhenTimerEnds }
        set { update { $0.stopAudioWhenTimerEnds = newValue } }
    }

    public var soundEnabled: Bool {
        get { settings.soundEnabled }
        set { update { $0.soundEnabled = newValue } }
    }

    // MARK: - Timer

    public var lastFocusMinutes: Int {
        get { settings.lastFocusMinutes }
        set { update { $0.lastFocusMinutes = FocusDuration.clamp(newValue) } }
    }

    public var timerSnapshot: FocusTimerSnapshot? {
        get { settings.timerSnapshot }
        set { update { $0.timerSnapshot = newValue } }
    }

    // MARK: - Desktop atmosphere

    public var desktopMode: DesktopAtmosphereMode {
        get { settings.desktopMode }
        set { update { $0.desktopMode = newValue } }
    }

    public var desktopFollowsEnvironment: Bool {
        get { settings.desktopFollowsEnvironment }
        set { update { $0.desktopFollowsEnvironment = newValue } }
    }

    public var desktopAnimationEnabled: Bool {
        get { settings.desktopAnimationEnabled }
        set { update { $0.desktopAnimationEnabled = newValue } }
    }

    public var desktopAnimationIntensity: DesktopAnimationIntensity {
        get { settings.desktopAnimationIntensity }
        set { update { $0.desktopAnimationIntensity = newValue } }
    }

    public var desktopEffects: DesktopEffects {
        get { settings.desktopEffects }
        set { update { $0.desktopEffects = newValue.normalized } }
    }

    public var desktopDisplay: DesktopDisplaySelection {
        get { settings.desktopDisplay }
        set {
            update {
                $0.desktopDisplay = newValue
                $0.desktopDisplay.normalize()
            }
        }
    }

    public var desktopAppliedEnvironment: EnvironmentID? {
        get { settings.desktopAppliedEnvironment }
        set { update { $0.desktopAppliedEnvironment = newValue } }
    }

    public var desktopOriginalWallpapers: [String: OriginalWallpaper] {
        settings.desktopOriginalWallpapers
    }

    public var hasOriginalWallpapers: Bool {
        !settings.desktopOriginalWallpapers.isEmpty
    }

    public func recordOriginalWallpaper(_ original: OriginalWallpaper, for displayID: String) {
        guard !displayID.isEmpty else { return }
        update { $0.desktopOriginalWallpapers[displayID] = original }
    }

    public func removeOriginalWallpaper(for displayID: String) {
        update { $0.desktopOriginalWallpapers.removeValue(forKey: displayID) }
    }

    public func clearOriginalWallpapers() {
        update { $0.desktopOriginalWallpapers = [:] }
    }

    // MARK: - Mixes

    public func savedMix(for environment: EnvironmentID) -> SavedMix? {
        settings.savedMixes[environment.rawValue]
    }

    public func hasSavedMix(for environment: EnvironmentID) -> Bool {
        savedMix(for: environment) != nil
    }

    public func saveMix(_ mix: SavedMix, for environment: EnvironmentID) {
        update { $0.savedMixes[environment.rawValue] = mix }
    }

    public func clearMix(for environment: EnvironmentID) {
        update { $0.savedMixes.removeValue(forKey: environment.rawValue) }
    }

    // MARK: - Persistence

    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        persistNow()
    }

    private func update(_ mutation: (inout AtmoraSettings) -> Void) {
        var copy = settings
        mutation(&copy)
        copy.normalize()
        settings = copy
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: storageKey)
            persistenceIssue = nil
        } catch {
            persistenceIssue = "Preferences could not be saved."
        }
    }
}
