import Foundation
import AtmoraCore

/// Isolated preferences domain so tests never touch the user's settings.
@MainActor
final class TestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "atmora.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeStore(storageKey: String = "atmora.settings.v1") -> PreferencesStore {
        PreferencesStore(defaults: defaults, storageKey: storageKey)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
final class MockAudioEngine: AudioPlaybackEngine {
    struct PlayCall {
        let environment: SoundEnvironment
        let levels: [String: Double]
        let masterVolume: Double
        let fadeIn: TimeInterval
    }

    struct CrossfadeCall {
        let environment: SoundEnvironment
        let levels: [String: Double]
        let duration: TimeInterval
    }

    private(set) var isRunning = false

    var playCalls: [PlayCall] = []
    var crossfadeCalls: [CrossfadeCall] = []
    var appliedLevels: [String: Double] = [:]
    var appliedEnvironment: EnvironmentID?
    var appliedVolumes: [Double] = []
    var fadeOutDurations: [TimeInterval] = []
    var stopImmediatelyCount = 0

    var failOnPlay = false
    var failOnCrossfade = false

    enum EngineError: Error, LocalizedError {
        case unavailable

        var errorDescription: String? { "The test engine is unavailable." }
    }

    func play(
        environment: SoundEnvironment,
        levels: [String: Double],
        masterVolume: Double,
        fadeIn: TimeInterval
    ) throws {
        if failOnPlay { throw EngineError.unavailable }
        playCalls.append(PlayCall(environment: environment, levels: levels, masterVolume: masterVolume, fadeIn: fadeIn))
        isRunning = true
    }

    func crossfade(
        to environment: SoundEnvironment,
        levels: [String: Double],
        duration: TimeInterval
    ) throws {
        if failOnCrossfade { throw EngineError.unavailable }
        crossfadeCalls.append(CrossfadeCall(environment: environment, levels: levels, duration: duration))
        isRunning = true
    }

    func applyLevels(_ levels: [String: Double], for environment: EnvironmentID) {
        appliedLevels = levels
        appliedEnvironment = environment
    }

    func setMasterVolume(_ volume: Double) {
        appliedVolumes.append(volume)
    }

    func fadeOutAndStop(duration: TimeInterval) {
        fadeOutDurations.append(duration)
        isRunning = false
    }

    func stopImmediately() {
        stopImmediatelyCount += 1
        isRunning = false
    }

    func playClick() {}
}
