import Foundation
import Observation

public enum PlaybackState: String, Sendable, Equatable {
    case idle
    case playing
    case paused

    public var isPlaying: Bool { self == .playing }
}

public struct LayerSetting: Identifiable, Hashable, Sendable {
    public let id: String
    public var level: Double
    public var isMuted: Bool

    public init(id: String, level: Double, isMuted: Bool = false) {
        self.id = id
        self.level = level
        self.isMuted = isMuted
    }

    public var effectiveLevel: Double {
        isMuted ? 0 : min(max(level, 0), 1)
    }
}

/// The playback layer is intentionally independent of AVFoundation. It owns
/// user intent and transitions, while `AudioPlaybackEngine` owns the audio graph.
@MainActor
public protocol AudioPlaybackEngine: AnyObject {
    var isRunning: Bool { get }
    func play(
        environment: SoundEnvironment,
        levels: [String: Double],
        masterVolume: Double,
        fadeIn: TimeInterval
    ) throws
    func crossfade(
        to environment: SoundEnvironment,
        levels: [String: Double],
        duration: TimeInterval
    ) throws
    func applyLevels(_ levels: [String: Double], for environment: EnvironmentID)
    func setMasterVolume(_ volume: Double)
    func fadeOutAndStop(duration: TimeInterval)
    func stopImmediately()
    /// Play a short UI click sound for environment changes.
    func playClick()
}

@MainActor
@Observable
public final class PlaybackController {
    public let catalog: EnvironmentCatalog
    public let preferences: PreferencesStore
    public let assetReport: AudioAssetReport

    public private(set) var selectedEnvironmentID: EnvironmentID
    public private(set) var state: PlaybackState = .idle
    public private(set) var masterVolume: Double
    public private(set) var layerSettings: [LayerSetting]
    public private(set) var errorMessage: String?
    public private(set) var lastMixSavedAt: Date?

    /// Called after a user-initiated environment change. The app uses this to
    /// synchronize the optional desktop wallpaper without observing every UI
    /// update.
    public var onSelectionChanged: ((EnvironmentID) -> Void)?

    private let audio: AudioPlaybackEngine

    public init(
        catalog: EnvironmentCatalog = .standard,
        preferences: PreferencesStore,
        audio: AudioPlaybackEngine,
        assetReport: AudioAssetReport = .allAvailable()
    ) {
        self.catalog = catalog
        self.preferences = preferences
        self.audio = audio
        self.assetReport = assetReport

        let restoredID = preferences.restoreLastEnvironment ? preferences.lastEnvironment : .rainyCabin
        let initialID = catalog[restoredID] != nil ? restoredID : .rainyCabin
        self.selectedEnvironmentID = initialID
        self.masterVolume = preferences.lastMasterVolume
        if let environment = catalog[initialID] {
            self.layerSettings = Self.makeLayerSettings(for: environment, preferences: preferences)
        } else {
            self.layerSettings = []
        }
    }

    public var selectedEnvironment: SoundEnvironment {
        catalog[selectedEnvironmentID] ?? catalog.environments[0]
    }

    public var isPlaying: Bool { state == .playing }

    /// Sound is a first-class atmosphere switch, separate from play/pause.
    public var isSoundEnabled: Bool { preferences.soundEnabled }

    public var isSelectedEnvironmentAvailable: Bool {
        assetReport.available.contains(selectedEnvironmentID)
    }

    public var selectedEnvironmentIssue: String? {
        guard !isSelectedEnvironmentAvailable else { return nil }
        if let issue = assetReport.message(for: selectedEnvironmentID) {
            return "\(selectedEnvironment.name) is unavailable. \(issue)"
        }
        return "\(selectedEnvironment.name) is unavailable because its audio files are missing."
    }

    public var hasSavedMix: Bool {
        preferences.hasSavedMix(for: selectedEnvironmentID)
    }

    public var effectiveLevels: [String: Double] {
        Dictionary(uniqueKeysWithValues: layerSettings.map { ($0.id, $0.effectiveLevel) })
    }

    /// Called by the app after launch. Never starts audio unexpectedly unless
    /// the user explicitly opted into resuming playback.
    public func restorePlaybackIfNeeded() {
        guard preferences.resumePlaybackOnLaunch else { return }
        guard preferences.soundEnabled else { return }
        guard isSelectedEnvironmentAvailable else { return }
        play()
    }

    public func togglePlayback() {
        switch state {
        case .playing:
            pause()
        case .idle, .paused:
            play()
        }
    }

    /// Turning sound off fades playback out immediately and remembers the
    /// selected environment. Turning it back on never starts audio by itself.
    public func setSoundEnabled(_ enabled: Bool) {
        guard preferences.soundEnabled != enabled else { return }
        if !enabled {
            pause()
            errorMessage = nil
        }
        preferences.soundEnabled = enabled
    }

    public func play() {
        guard state != .playing else { return }
        guard preferences.soundEnabled else { return }
        guard isSelectedEnvironmentAvailable else {
            errorMessage = selectedEnvironmentIssue
            return
        }

        let environment = selectedEnvironment
        do {
            try audio.play(
                environment: environment,
                levels: effectiveLevels,
                masterVolume: masterVolume,
                fadeIn: preferences.fadeInSeconds
            )
            state = .playing
            errorMessage = nil
        } catch {
            state = .idle
            audio.stopImmediately()
            errorMessage = "Atmora couldn't start \(environment.name). \(error.localizedDescription)"
        }
        persistSession()
    }

    public func pause() {
        guard state == .playing else { return }
        audio.fadeOutAndStop(duration: preferences.fadeOutSeconds)
        state = .paused
        errorMessage = nil
        persistSession()
    }

    /// Selecting while paused or idle never starts playback.
    public func select(_ id: EnvironmentID) {
        guard id != selectedEnvironmentID, let environment = catalog[id] else { return }

        selectedEnvironmentID = id
        layerSettings = Self.makeLayerSettings(for: environment, preferences: preferences)
        lastMixSavedAt = nil
        preferences.lastEnvironment = id
        onSelectionChanged?(id)

        // Aesthetic click on every environment change.
        audio.playClick()

        guard state == .playing else {
            errorMessage = nil
            return
        }

        guard assetReport.available.contains(id) else {
            audio.fadeOutAndStop(duration: preferences.fadeOutSeconds)
            state = .idle
            errorMessage = selectedEnvironmentIssue
            return
        }

        do {
            try audio.crossfade(
                to: environment,
                levels: effectiveLevels,
                duration: max(preferences.fadeInSeconds, 0.4)
            )
            errorMessage = nil
        } catch {
            state = .idle
            audio.stopImmediately()
            errorMessage = "Atmora couldn't switch to \(environment.name). \(error.localizedDescription)"
        }
    }

    public func selectNext() {
        let ids = catalog.environments.map(\.id)
        guard let index = ids.firstIndex(of: selectedEnvironmentID) else { return }
        select(ids[(index + 1) % ids.count])
    }

    public func selectPrevious() {
        let ids = catalog.environments.map(\.id)
        guard let index = ids.firstIndex(of: selectedEnvironmentID) else { return }
        select(ids[(index - 1 + ids.count) % ids.count])
    }

    public func setMasterVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        guard abs(clamped - masterVolume) > 0.0001 else { return }
        masterVolume = clamped
        preferences.lastMasterVolume = clamped
        audio.setMasterVolume(clamped)
    }

    public func setLayerLevel(_ layerID: String, level: Double) {
        guard let index = layerSettings.firstIndex(where: { $0.id == layerID }) else { return }
        let clamped = min(max(level, 0), 1)
        guard abs(layerSettings[index].level - clamped) > 0.0001 else { return }
        layerSettings[index].level = clamped
        audio.applyLevels(effectiveLevels, for: selectedEnvironmentID)
        lastMixSavedAt = nil
    }

    public func toggleMute(_ layerID: String) {
        guard let index = layerSettings.firstIndex(where: { $0.id == layerID }) else { return }
        layerSettings[index].isMuted.toggle()
        audio.applyLevels(effectiveLevels, for: selectedEnvironmentID)
        lastMixSavedAt = nil
    }

    /// Restores the environment's intended preset levels and removes any saved
    /// custom mix so the reset survives a relaunch.
    public func resetMix() {
        let environment = selectedEnvironment
        layerSettings = environment.layers.map {
            LayerSetting(id: $0.id, level: $0.defaultLevel, isMuted: false)
        }
        preferences.clearMix(for: selectedEnvironmentID)
        audio.applyLevels(effectiveLevels, for: selectedEnvironmentID)
        lastMixSavedAt = nil
    }

    public func saveMix() {
        let mix = SavedMix(
            levels: Dictionary(uniqueKeysWithValues: layerSettings.map { ($0.id, $0.level) }),
            muted: Set(layerSettings.filter(\.isMuted).map(\.id)),
            savedAt: Date()
        )
        preferences.saveMix(mix, for: selectedEnvironmentID)
        lastMixSavedAt = mix.savedAt
    }

    /// Used when a focus session ends. The engine performs a long, click-free
    /// fade; playback state becomes paused and the selected environment stays.
    public func fadeOutForTimer(duration: TimeInterval) {
        guard state == .playing else { return }
        audio.fadeOutAndStop(duration: max(duration, 1))
        state = .paused
    }

    public func retryAfterFailure() {
        errorMessage = nil
        play()
    }

    public func clearError() {
        errorMessage = nil
    }

    /// Called by the audio engine when the output device changes and playback
    /// cannot be recovered. The UI remains consistent and can retry.
    public func reportAudioFailure(_ message: String) {
        if state == .playing {
            state = .idle
        }
        errorMessage = message
    }

    public func shutdown() {
        audio.stopImmediately()
        state = .idle
        persistSession()
    }

    private func persistSession() {
        preferences.lastEnvironment = selectedEnvironmentID
        preferences.lastMasterVolume = masterVolume
    }

    private static func makeLayerSettings(
        for environment: SoundEnvironment,
        preferences: PreferencesStore
    ) -> [LayerSetting] {
        let saved = preferences.savedMix(for: environment.id)
        return environment.layers.map { layer in
            let level = saved?.levels[layer.id] ?? layer.defaultLevel
            return LayerSetting(
                id: layer.id,
                level: min(max(level, 0), 1),
                isMuted: saved?.muted.contains(layer.id) ?? false
            )
        }
    }
}
