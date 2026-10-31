import AppKit
import Foundation
import Observation
import SwiftUI
import AtmoraCore

/// Application-level owner of state, windows, the timer ticker, and integration
/// with the menu bar. There is exactly one coordinator for the app's lifetime.
@MainActor
@Observable
final class AppCoordinator {
    let catalog: EnvironmentCatalog
    let preferences: PreferencesStore
    let audioEngine: AudioEngineManager
    let playback: PlaybackController
    let focusTimer: FocusTimer
    let notifications = NotificationManager()
    let hotKeys = GlobalHotKeyManager()
    let desktop: DesktopAtmosphereController
    private(set) var assetReport: AudioAssetReport

    private(set) var isWindowVisible = false
    private(set) var shortcutIssue: String?
    private(set) var launchAtLoginIssue: String?

    @ObservationIgnored private var windowController: MainWindowController?
    @ObservationIgnored private var focusTicker: Timer?
    @ObservationIgnored private var hasStarted = false

    init() {
        Self.migrateLegacyPreferencesIfNeeded()

        let catalog = EnvironmentCatalog.standard
        let preferences = PreferencesStore()
        let audioDirectory = AppResources.audioDirectory()
        let audioEngine = AudioEngineManager(audioDirectory: audioDirectory)

        let report: AudioAssetReport
        if let audioDirectory {
            report = AudioAssetValidator.validate(catalog: catalog, audioDirectory: audioDirectory)
        } else {
            let issues = Dictionary(uniqueKeysWithValues: EnvironmentID.allCases.map {
                ($0, ["The bundled Audio folder could not be found."])
            })
            report = AudioAssetReport(available: [], issues: issues)
        }

        let playback = PlaybackController(
            catalog: catalog,
            preferences: preferences,
            audio: audioEngine,
            assetReport: report
        )

        self.catalog = catalog
        self.preferences = preferences
        self.audioEngine = audioEngine
        self.assetReport = report
        self.playback = playback
        self.focusTimer = FocusTimer()
        self.desktop = DesktopAtmosphereController(preferences: preferences, playback: playback)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        preferences.onThemeChanged = { [weak self] _ in
            self?.applyTheme()
        }
        preferences.onShortcutChanged = { [weak self] in
            self?.refreshGlobalShortcut()
        }
        audioEngine.onRuntimeFailure = { [weak self] message in
            self?.playback.reportAudioFailure(message)
        }
        hotKeys.setHandler { [weak self] in
            self?.toggleMainWindow()
        }
        playback.onSelectionChanged = { [weak self] environment in
            self?.desktop.environmentDidChange(to: environment)
        }
        focusTimer.onFinished = { [weak self] in
            self?.handleFocusTimerFinished()
        }

        applyTheme()
        refreshGlobalShortcut()
        syncLaunchAtLoginStatus()
        restoreFocusTimer()
        desktop.start()

        playback.restorePlaybackIfNeeded()
    }

    // MARK: - Window

    func showMainWindow() {
        ensureWindowController()
        windowController?.show()
        setWindowVisible(true)
    }

    func hideMainWindow() {
        windowController?.hide()
        setWindowVisible(false)
    }

    func toggleMainWindow() {
        if isWindowVisible && NSApp.isActive {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    func windowVisibilityChanged(_ visible: Bool) {
        isWindowVisible = visible
    }

    private func setWindowVisible(_ visible: Bool) {
        isWindowVisible = visible
    }

    private func ensureWindowController() {
        guard windowController == nil else { return }
        let root = MainWindowView()
            .environment(self)
        let controller = MainWindowController(rootView: AnyView(root))
        controller.onVisibilityChanged = { [weak self] visible in
            self?.windowVisibilityChanged(visible)
        }
        controller.applyAppearance(preferences.theme.appearance)
        windowController = controller
    }

    func applyTheme() {
        NSApp.appearance = preferences.theme.appearance
        windowController?.applyAppearance(preferences.theme.appearance)
    }

    // MARK: - Shortcut

    func refreshGlobalShortcut() {
        hotKeys.unregister()
        shortcutIssue = nil
        guard preferences.shortcutEnabled, let combo = preferences.shortcut else { return }
        if !hotKeys.register(combo) {
            shortcutIssue = hotKeys.lastError
        }
    }

    // MARK: - Launch at login

    func syncLaunchAtLoginStatus() {
        let enabled = LaunchAtLogin.isEnabled
        if preferences.launchAtLogin != enabled {
            preferences.launchAtLogin = enabled
        }
        launchAtLoginIssue = LaunchAtLogin.requiresApproval ? LaunchAtLogin.statusDescription : nil
    }

    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            preferences.launchAtLogin = enabled
            launchAtLoginIssue = LaunchAtLogin.requiresApproval ? LaunchAtLogin.statusDescription : nil
            return nil
        } catch {
            preferences.launchAtLogin = LaunchAtLogin.isEnabled
            let message = "Launch at login could not be changed: \(error.localizedDescription)"
            launchAtLoginIssue = message
            return message
        }
    }

    // MARK: - Notifications

    func setNotificationsEnabled(_ enabled: Bool) async -> String? {
        if enabled {
            let granted = await notifications.requestAuthorization()
            guard granted else {
                preferences.notificationsEnabled = false
                return notifications.lastError ?? "Notifications could not be enabled."
            }
            preferences.notificationsEnabled = true
            if focusTimer.phase == .running {
                await notifications.scheduleCompletion(after: focusTimer.remaining)
            }
            return nil
        } else {
            preferences.notificationsEnabled = false
            notifications.cancelCompletion()
            return nil
        }
    }

    // MARK: - Focus timer

    func startFocus(minutes: Int) {
        let clamped = FocusDuration.clamp(minutes)
        focusTimer.start(minutes: clamped)
        preferences.lastFocusMinutes = clamped
        persistTimerSnapshot()
        startFocusTicker()
        scheduleFocusNotificationIfNeeded()
    }

    func pauseFocus() {
        guard focusTimer.phase == .running else { return }
        focusTimer.pause()
        stopFocusTicker()
        persistTimerSnapshot()
        notifications.cancelCompletion()
    }

    func resumeFocus() {
        guard focusTimer.phase == .paused else { return }
        focusTimer.resume()
        persistTimerSnapshot()
        startFocusTicker()
        scheduleFocusNotificationIfNeeded()
    }

    func cancelFocus() {
        focusTimer.cancel()
        stopFocusTicker()
        preferences.timerSnapshot = nil
        notifications.cancelCompletion()
    }

    func dismissFinishedFocus() {
        focusTimer.dismissFinished()
        preferences.timerSnapshot = nil
    }

    private func startFocusTicker() {
        stopFocusTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.focusTimer.refresh()
                if self.focusTimer.phase != .running {
                    self.stopFocusTicker()
                }
            }
        }
        timer.tolerance = 0.12
        RunLoop.main.add(timer, forMode: .common)
        focusTicker = timer
    }

    private func stopFocusTicker() {
        focusTicker?.invalidate()
        focusTicker = nil
    }

    private func persistTimerSnapshot() {
        preferences.timerSnapshot = focusTimer.snapshot
    }

    private func restoreFocusTimer() {
        guard let snapshot = preferences.timerSnapshot else { return }
        let active = focusTimer.restore(snapshot)
        if active {
            if focusTimer.phase == .running {
                startFocusTicker()
                scheduleFocusNotificationIfNeeded()
            }
        } else {
            preferences.timerSnapshot = nil
        }
    }

    private func scheduleFocusNotificationIfNeeded() {
        guard preferences.notificationsEnabled else { return }
        let remaining = focusTimer.remaining
        Task { [weak self] in
            await self?.notifications.scheduleCompletion(after: remaining)
        }
    }

    private func handleFocusTimerFinished() {
        stopFocusTicker()
        preferences.timerSnapshot = nil
        // The pending local notification, if enabled, is allowed to fire.
        if preferences.stopAudioWhenTimerEnds {
            playback.fadeOutForTimer(duration: 8)
        }
    }

    // MARK: - Lifecycle

    func shutdown() {
        stopFocusTicker()
        preferences.timerSnapshot = focusTimer.snapshot
        desktop.shutdown()
        preferences.flush()
        playback.shutdown()
        audioEngine.shutdown()
        hotKeys.unregister()
    }

    // MARK: - Atmosphere

    /// Sound is an atmosphere switch, not a second play button. Turning it off
    /// fades out gracefully; turning it on leaves playback paused until asked.
    func setSoundEnabled(_ enabled: Bool) {
        playback.setSoundEnabled(enabled)
    }

    /// Desktop ON means the animated Living Desktop preview follows the selected
    /// room — it always moves, never a still wallpaper. OFF keeps Atmora
    /// inside its own window.
    func setDesktopEnabled(_ enabled: Bool) {
        if enabled {
            desktop.setMode(.livingDesktop)
        } else {
            desktop.setMode(.appOnly)
        }
    }

    func setDesktopMode(_ mode: DesktopAtmosphereMode) {
        desktop.setMode(mode)
    }

    func setDesktopFollowsEnvironment(_ follows: Bool) {
        desktop.setFollowsEnvironment(follows)
    }

    func setDesktopDisplay(_ selection: DesktopDisplaySelection) {
        desktop.setDisplay(selection)
    }

    func setDesktopAnimationEnabled(_ enabled: Bool) {
        desktop.setAnimationEnabled(enabled)
    }

    func setDesktopAnimationIntensity(_ intensity: DesktopAnimationIntensity) {
        desktop.setAnimationIntensity(intensity)
    }

    func setDesktopEffects(_ effects: DesktopEffects) {
        desktop.setEffects(effects)
    }

    func restoreOriginalWallpaper() {
        desktop.restoreOriginalWallpapers()
    }

    func toggleLivingDesktopPreview() {
        desktop.togglePreview()
    }

    /// The bundle identifier changed from the first local build. Copy the old
    /// settings payload once so existing mixes and timer state survive.
    private static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "atmora.settings.v1"
        guard defaults.data(forKey: key) == nil else { return }

        let currentBundleID = Bundle.main.bundleIdentifier
        for legacy in ["com.example.atmora"] where legacy != currentBundleID {
            guard let legacyDefaults = UserDefaults(suiteName: legacy),
                  let data = legacyDefaults.data(forKey: key) else { continue }
            defaults.set(data, forKey: key)
            return
        }
    }

    var startupNotice: String? {
        preferences.loadIssue
    }
}
