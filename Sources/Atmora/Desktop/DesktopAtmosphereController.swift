import AppKit
import CoreGraphics
import Observation
import SwiftUI
import AtmoraCore

/// Owns every interaction with the macOS desktop. The app only calls into this
/// controller for explicit user actions or a genuine environment change, which
/// keeps Atmora from rewriting the wallpaper during unrelated UI updates.
@MainActor
@Observable
final class DesktopAtmosphereController {
    struct ScreenOption: Identifiable, Hashable {
        let id: String
        let name: String
        let isMain: Bool
        let resolution: String
    }

    private struct Target {
        let screen: NSScreen
        let id: String
        let name: String
    }

    private let preferences: PreferencesStore
    private let playback: PlaybackController
    private let workspace = NSWorkspace.shared
    private let preview = LivingDesktopPreviewController()

    private(set) var screenOptions: [ScreenOption] = []
    private(set) var lastError: String?
    private(set) var lastStatus: String?
    private(set) var isPreviewVisible = false

    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(preferences: PreferencesStore, playback: PlaybackController) {
        self.preferences = preferences
        self.playback = playback
        refreshScreens()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Lifecycle

    func start() {
        refreshScreens()
        // Diagnostic runs must never touch the user's desktop.
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("--audio-smoke-test"), !arguments.contains("--asset-check") else { return }

        // Living Desktop is a window-based preview. Earlier builds also wrote a
        // still wallpaper; put the user's own wallpaper back before doing
        // anything else, so the app leaves no trace of that behaviour.
        restoreRecordedOriginals()

        guard preferences.desktopMode.usesDesktopWallpaper else { return }

        if preferences.desktopMode == .livingDesktop, preferences.desktopAnimationEnabled {
            showPreview()
        }
    }

    func shutdown() {
        hidePreview()
        // Quitting must leave the desktop exactly as it was found. This also
        // cleans up wallpaper files written by older versions of Atmora.
        restoreRecordedOriginals()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    // MARK: - Settings actions

    func setMode(_ mode: DesktopAtmosphereMode) {
        let previous = preferences.desktopMode
        guard mode != previous else { return }

        if mode == .appOnly {
            hidePreview()
            restoreRecordedOriginals()
            preferences.desktopMode = .appOnly
            return
        }

        preferences.desktopMode = mode
        if mode == .livingDesktop, preferences.desktopAnimationEnabled {
            showPreview()
        } else {
            hidePreview()
        }
    }

    func setFollowsEnvironment(_ follows: Bool) {
        preferences.desktopFollowsEnvironment = follows
    }

    func setDisplay(_ selection: DesktopDisplaySelection) {
        preferences.desktopDisplay = selection
        guard preferences.desktopMode == .livingDesktop, isPreviewVisible else { return }
        hidePreview()
        showPreview()
    }

    func setAnimationEnabled(_ enabled: Bool) {
        preferences.desktopAnimationEnabled = enabled
        guard preferences.desktopMode == .livingDesktop else { return }
        if enabled {
            showPreview()
        } else {
            hidePreview()
        }
    }

    func setAnimationIntensity(_ intensity: DesktopAnimationIntensity) {
        preferences.desktopAnimationIntensity = intensity
        guard isPreviewVisible else { return }
        preview.update(
            environment: playback.selectedEnvironmentID,
            intensity: intensity,
            effects: preferences.desktopEffects
        )
    }

    func setEffects(_ effects: DesktopEffects) {
        preferences.desktopEffects = effects
        guard isPreviewVisible else { return }
        preview.update(
            environment: playback.selectedEnvironmentID,
            intensity: preferences.desktopAnimationIntensity,
            effects: preferences.desktopEffects
        )
    }

    func togglePreview() {
        guard preferences.desktopMode == .livingDesktop else { return }
        if isPreviewVisible {
            hidePreview()
        } else if preferences.desktopAnimationEnabled {
            showPreview()
        }
    }

    /// Called by the playback controller only after a real user selection.
    func environmentDidChange(to environment: EnvironmentID) {
        guard isPreviewVisible else { return }
        preview.update(
            environment: environment,
            intensity: preferences.desktopAnimationIntensity,
            effects: preferences.desktopEffects
        )
    }

    func restoreOriginalWallpapers() {
        let saved = preferences.desktopOriginalWallpapers
        guard !saved.isEmpty else {
            lastError = "Atmora has not recorded an original wallpaper yet."
            return
        }

        let outcome = restoreAllRecordedOriginals()

        preferences.desktopMode = .appOnly
        preferences.desktopAppliedEnvironment = nil
        hidePreview()

        finishRestore(outcome)
    }

    // MARK: - Derived state

    var displaySummary: String {
        switch preferences.desktopDisplay.scope {
        case .all:
            let count = screenOptions.count
            if count == 0 { return "all displays" }
            return count == 1 ? "the connected display" : "all \(count) displays"
        case .main:
            return "the main display"
        case .specific:
            guard let uuid = preferences.desktopDisplay.displayUUID else { return "the selected display" }
            return screenOptions.first(where: { $0.id == uuid })?.name ?? "the selected display"
        }
    }

    var selectedDisplayIsConnected: Bool {
        guard preferences.desktopDisplay.scope == .specific,
              let uuid = preferences.desktopDisplay.displayUUID else { return true }
        return screenOptions.contains { $0.id == uuid }
    }

    var appliedEnvironmentName: String? {
        guard let environment = preferences.desktopAppliedEnvironment,
              let name = playback.catalog[environment]?.name else { return nil }
        return name
    }

    // MARK: - Legacy wallpaper cleanup

    private struct RestoreOutcome {
        var restored = 0
        var clearedLeftovers = 0
        var failures: [String] = []
    }

    /// Puts back any wallpaper recorded by earlier builds, then forgets the
    /// record. Living Desktop no longer writes a system wallpaper, so this is
    /// the only wallpaper path left in the app.
    private func restoreRecordedOriginals() {
        preferences.desktopAppliedEnvironment = nil
        guard preferences.hasOriginalWallpapers else { return }
        finishRestore(restoreAllRecordedOriginals())
    }

    /// Restores each recorded original. When macOS could not record a path
    /// (for example a dynamic wallpaper), but the display is still showing a
    /// Atmora wallpaper, the system default is applied so the app leaves no
    /// visible trace. The record is then cleared.
    private func restoreAllRecordedOriginals() -> RestoreOutcome {
        var outcome = RestoreOutcome()

        for (displayID, original) in preferences.desktopOriginalWallpapers {
            if restore(original, displayID: displayID) {
                preferences.removeOriginalWallpaper(for: displayID)
                outcome.restored += 1
            } else if clearLeftoverAtmoraWallpaper(for: displayID) {
                preferences.removeOriginalWallpaper(for: displayID)
                outcome.restored += 1
                outcome.clearedLeftovers += 1
            } else {
                outcome.failures.append(displayName(for: displayID))
            }
        }

        return outcome
    }

    private func finishRestore(_ outcome: RestoreOutcome) {
        if outcome.failures.isEmpty {
            lastError = nil
            if outcome.restored > 0 {
                if outcome.clearedLeftovers > 0 {
                    lastStatus = "Removed Atmora's leftover wallpaper. Open System Settings › Wallpaper to choose your preferred picture."
                } else {
                    lastStatus = "Restored your original wallpaper on \(outcome.restored == 1 ? "1 display" : "\(outcome.restored) displays")."
                }
            }
        } else {
            lastError = "Some original wallpapers could not be restored: \(outcome.failures.joined(separator: ", ")). Open System Settings › Wallpaper to set them manually."
            lastStatus = outcome.restored > 0 ? "Restored \(outcome.restored) display(s)." : nil
        }
    }

    /// Applies the macOS default desktop only when Atmora's own wallpaper is
    /// currently visible, so this can never overwrite a wallpaper the user
    /// chose after Atmora wrote one.
    private func clearLeftoverAtmoraWallpaper(for displayID: String) -> Bool {
        guard let screen = screen(for: displayID),
              let current = workspace.desktopImageURL(for: screen),
              isAtmoraWallpaper(current) else { return false }

        let fallback = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
        guard FileManager.default.fileExists(atPath: fallback.path) else { return false }

        do {
            try workspace.setDesktopImageURL(fallback, for: screen, options: [:])
            return true
        } catch {
            return false
        }
    }

    private func isAtmoraWallpaper(_ url: URL) -> Bool {
        guard let directory = AppResources.wallpaperDirectory() else { return false }
        let root = directory.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(root + "/")
    }

    private func restore(_ original: OriginalWallpaper, displayID: String) -> Bool {
        guard let screen = screen(for: displayID) else {
            // The display is disconnected. Keep the record so it can be
            // restored when it returns.
            return false
        }
        guard let path = original.urlPath, !path.isEmpty else {
            lastError = "macOS did not report a restorable wallpaper file for \(screen.localizedName). It may be a dynamic wallpaper; restore it in System Settings › Wallpaper."
            return false
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "The original wallpaper for \(screen.localizedName) is no longer at \(path)."
            return false
        }

        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = original.imageScalingRawValue {
            options[.imageScaling] = NSNumber(value: scaling)
        }
        if let clipping = original.allowsClipping {
            options[.allowClipping] = NSNumber(value: clipping)
        }

        do {
            try workspace.setDesktopImageURL(url, for: screen, options: options)
            return true
        } catch {
            lastError = "The original wallpaper for \(screen.localizedName) could not be restored: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Living Desktop preview

    private func showPreview() {
        guard preferences.desktopMode == .livingDesktop,
              preferences.desktopAnimationEnabled else { return }

        let targets = targetScreens()
        guard !targets.isEmpty else {
            lastError = "The selected display is not connected, so the Living Desktop preview was not opened."
            return
        }

        preview.show(
            screens: targets.map { ($0.screen, $0.id) },
            environment: playback.selectedEnvironmentID,
            intensity: preferences.desktopAnimationIntensity,
            effects: preferences.desktopEffects
        )
        isPreviewVisible = true
        lastError = nil
        lastStatus = "Living Desktop preview is showing on \(displaySummary). It is a window-based preview, not a system wallpaper."
    }

    private func hidePreview() {
        preview.hide()
        isPreviewVisible = false
    }

    // MARK: - Screens

    private func refreshScreens() {
        let mainID = NSScreen.main.flatMap { Self.displayUUID(for: $0) }
        screenOptions = NSScreen.screens.compactMap { screen in
            guard let id = Self.displayUUID(for: screen) else { return nil }
            let scale = screen.backingScaleFactor
            let width = Int(screen.frame.width * scale)
            let height = Int(screen.frame.height * scale)
            return ScreenOption(
                id: id,
                name: screen.localizedName,
                isMain: id == mainID,
                resolution: "\(width) × \(height)"
            )
        }
    }

    private func screensChanged() {
        refreshScreens()
        if !selectedDisplayIsConnected {
            lastError = "The selected display is no longer connected. Choose another display to show the Living Desktop preview."
        }
    }

    private func targetScreens() -> [Target] {
        let selection = preferences.desktopDisplay
        switch selection.scope {
        case .all:
            return NSScreen.screens.compactMap { target(for: $0) }
        case .main:
            guard let main = NSScreen.main, let target = target(for: main) else { return [] }
            return [target]
        case .specific:
            guard let uuid = selection.displayUUID else { return [] }
            return NSScreen.screens.compactMap { screen in
                guard let target = target(for: screen), target.id == uuid else { return nil }
                return target
            }
        }
    }

    private func target(for screen: NSScreen) -> Target? {
        guard let id = Self.displayUUID(for: screen) else { return nil }
        return Target(screen: screen, id: id, name: screen.localizedName)
    }

    private func screen(for displayID: String) -> NSScreen? {
        NSScreen.screens.first { Self.displayUUID(for: $0) == displayID }
    }

    private func displayName(for displayID: String) -> String {
        screen(for: displayID)?.localizedName ?? "a disconnected display"
    }

    static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

}
