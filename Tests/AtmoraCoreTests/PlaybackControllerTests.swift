import Foundation
import Testing
@testable import AtmoraCore

@MainActor
@Suite("Playback controller")
struct PlaybackControllerTests {
    private struct Context {
        let defaults: TestDefaults
        let preferences: PreferencesStore
        let engine: MockAudioEngine
        let controller: PlaybackController
    }

    private func makeContext(
        report: AudioAssetReport = .allAvailable(),
        configure: ((PreferencesStore) -> Void)? = nil
    ) -> Context {
        let defaults = TestDefaults()
        let preferences = defaults.makeStore()
        configure?(preferences)
        let engine = MockAudioEngine()
        let controller = PlaybackController(
            preferences: preferences,
            audio: engine,
            assetReport: report
        )
        return Context(defaults: defaults, preferences: preferences, engine: engine, controller: controller)
    }

    private func level(_ controller: PlaybackController, _ layerID: String) -> Double? {
        controller.layerSettings.first { $0.id == layerID }?.level
    }

    private func isMuted(_ controller: PlaybackController, _ layerID: String) -> Bool? {
        controller.layerSettings.first { $0.id == layerID }?.isMuted
    }

    @Test("Play, pause, and resume update state and audio calls")
    func playAndPause() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        #expect(context.controller.state == .idle)
        #expect(!context.controller.isPlaying)

        context.controller.play()
        #expect(context.controller.state == .playing)
        #expect(context.engine.playCalls.count == 1)
        #expect(context.engine.playCalls.first?.environment.id == .rainyCabin)
        #expect(context.engine.playCalls.first?.fadeIn == context.preferences.fadeInSeconds)
        #expect(context.engine.playCalls.first?.masterVolume == context.controller.masterVolume)
        #expect(context.engine.playCalls.first?.levels["rain"] == 0.78)

        context.controller.pause()
        #expect(context.controller.state == .paused)
        #expect(context.engine.fadeOutDurations == [context.preferences.fadeOutSeconds])

        context.controller.play()
        #expect(context.controller.state == .playing)
        #expect(context.engine.playCalls.count == 2)
    }

    @Test("Selecting while idle never starts audio")
    func selectionDoesNotStartAudio() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.select(.sunsetDrive)

        #expect(context.controller.selectedEnvironmentID == .sunsetDrive)
        #expect(context.controller.state == .idle)
        #expect(context.engine.playCalls.isEmpty)
        #expect(context.engine.crossfadeCalls.isEmpty)
        #expect(context.controller.errorMessage == nil)
        #expect(context.preferences.lastEnvironment == .sunsetDrive)
    }

    @Test("Selecting while playing crossfades")
    func crossfadeOnSelection() throws {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.play()
        context.controller.select(.seasideRecords)

        #expect(context.controller.selectedEnvironmentID == .seasideRecords)
        #expect(context.controller.state == .playing)
        #expect(context.engine.crossfadeCalls.count == 1)
        #expect(context.engine.crossfadeCalls.first?.environment.id == .seasideRecords)
        #expect(context.engine.crossfadeCalls.first?.levels["waves"] == 0.68)
        let duration = try #require(context.engine.crossfadeCalls.first?.duration)
        #expect(duration >= 0.4)
    }

    @Test("Next and previous wrap around the catalogue")
    func selectionWraps() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.select(.seasideRecords)
        context.controller.selectNext()
        #expect(context.controller.selectedEnvironmentID == .rainyCabin)

        context.controller.selectPrevious()
        #expect(context.controller.selectedEnvironmentID == .seasideRecords)
    }

    @Test("An unavailable environment cannot start")
    func unavailableCannotStart() {
        let report = AudioAssetReport(
            available: [.rainyCabin],
            issues: [.sunsetDrive: ["Sunset Drive: the audio files are missing."]]
        )
        let context = makeContext(report: report)
        defer { context.defaults.cleanUp() }

        context.controller.select(.sunsetDrive)
        #expect(!context.controller.isSelectedEnvironmentAvailable)
        #expect(context.controller.selectedEnvironmentIssue != nil)

        context.controller.play()

        #expect(context.controller.state == .idle)
        #expect(context.engine.playCalls.isEmpty)
        #expect(context.controller.errorMessage != nil)
    }

    @Test("Switching to unavailable audio during playback fades out")
    func unavailableDuringPlayback() {
        let report = AudioAssetReport(
            available: [.rainyCabin],
            issues: [.sunsetDrive: ["Sunset Drive: the audio files are missing."]]
        )
        let context = makeContext(report: report)
        defer { context.defaults.cleanUp() }

        context.controller.play()
        context.controller.select(.sunsetDrive)

        #expect(context.controller.state == .idle)
        #expect(context.engine.fadeOutDurations.count == 1)
        #expect(context.engine.crossfadeCalls.isEmpty)
        #expect(context.controller.errorMessage != nil)
    }

    @Test("Layer levels clamp and mute silences a layer")
    func layerLevelsAndMuting() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.setLayerLevel("rain", level: 3)
        #expect(level(context.controller, "rain") == 1)
        #expect(context.engine.appliedLevels["rain"] == 1)
        #expect(context.engine.appliedEnvironment == .rainyCabin)

        context.controller.setLayerLevel("rain", level: -1)
        #expect(context.controller.effectiveLevels["rain"] == 0)

        context.controller.toggleMute("thunder")
        #expect(context.controller.effectiveLevels["thunder"] == 0)
        #expect(context.engine.appliedLevels["thunder"] == 0)
    }

    @Test("Master volume clamps and forwards")
    func masterVolume() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.setMasterVolume(2)
        #expect(context.controller.masterVolume == 1)
        #expect(context.engine.appliedVolumes.last == 1)

        context.controller.setMasterVolume(-1)
        #expect(context.controller.masterVolume == 0)
        #expect(context.engine.appliedVolumes.last == 0)
    }

    @Test("A saved mix survives relaunch and reset restores the preset")
    func savedMix() throws {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.setLayerLevel("rain", level: 0.2)
        context.controller.toggleMute("thunder")
        context.controller.saveMix()
        #expect(context.controller.hasSavedMix)
        #expect(context.controller.lastMixSavedAt != nil)
        context.preferences.flush()

        let reloadedPreferences = context.defaults.makeStore()
        let second = PlaybackController(preferences: reloadedPreferences, audio: MockAudioEngine())

        let savedRain = try #require(level(second, "rain"))
        #expect(abs(savedRain - 0.2) < 0.0001)
        #expect(isMuted(second, "thunder") == true)
        #expect(second.hasSavedMix)

        second.resetMix()

        let resetRain = try #require(level(second, "rain"))
        #expect(abs(resetRain - 0.78) < 0.0001)
        #expect(isMuted(second, "thunder") == false)
        #expect(!second.hasSavedMix)
        #expect(!reloadedPreferences.hasSavedMix(for: .rainyCabin))
    }

    @Test("Reset restores preset levels even without a saved mix")
    func resetWithoutSavedMix() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.setLayerLevel("rain", level: 0.2)
        context.controller.toggleMute("thunder")
        #expect(!context.controller.hasSavedMix)

        context.controller.resetMix()

        let resetRain = level(context.controller, "rain") ?? 0
        #expect(abs(resetRain - 0.78) < 0.0001)
        #expect(isMuted(context.controller, "thunder") == false)
        #expect(context.engine.appliedLevels["rain"] == 0.78)
    }

    @Test("An engine failure is reported and leaves the app consistent")
    func engineFailure() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.engine.failOnPlay = true
        context.controller.play()

        #expect(context.controller.state == .idle)
        #expect(context.engine.stopImmediatelyCount == 1)
        #expect(context.controller.errorMessage?.contains("couldn't start") == true)

        context.controller.clearError()
        #expect(context.controller.errorMessage == nil)
    }

    @Test("A runtime audio failure surfaces without crashing")
    func runtimeFailure() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.play()
        context.controller.reportAudioFailure("The output device changed.")

        #expect(context.controller.state == .idle)
        #expect(context.controller.errorMessage == "The output device changed.")
    }

    @Test("Resuming playback at launch is opt-in")
    func resumeAtLaunch() {
        let off = makeContext()
        defer { off.defaults.cleanUp() }
        off.controller.restorePlaybackIfNeeded()
        #expect(off.engine.playCalls.isEmpty)

        let on = makeContext { preferences in
            preferences.resumePlaybackOnLaunch = true
        }
        defer { on.defaults.cleanUp() }
        on.controller.restorePlaybackIfNeeded()
        #expect(on.controller.state == .playing)
        #expect(on.engine.playCalls.count == 1)
    }

    @Test("The last environment respects the restore preference")
    func restoreLastEnvironment() {
        let restored = makeContext { preferences in
            preferences.lastEnvironment = .rainyCabin
            preferences.restoreLastEnvironment = true
        }
        defer { restored.defaults.cleanUp() }
        #expect(restored.controller.selectedEnvironmentID == .rainyCabin)

        let ignored = makeContext { preferences in
            preferences.lastEnvironment = .rainyCabin
            preferences.restoreLastEnvironment = false
        }
        defer { ignored.defaults.cleanUp() }
        #expect(ignored.controller.selectedEnvironmentID == .rainyCabin)
    }

    @Test("Environment and volume persist across launches")
    func persistSession() throws {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.select(.rainyCabin)
        context.controller.setMasterVolume(0.31)
        context.controller.play()
        context.preferences.flush()

        let reloaded = context.defaults.makeStore()
        let second = PlaybackController(preferences: reloaded, audio: MockAudioEngine())

        #expect(second.selectedEnvironmentID == .rainyCabin)
        #expect(abs(second.masterVolume - 0.31) < 0.0001)
        #expect(second.state == .idle)
    }

    @Test("Timer fade-out pauses without clearing the environment")
    func timerFadeOut() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        context.controller.play()
        context.controller.fadeOutForTimer(duration: 8)

        #expect(context.controller.state == .paused)
        #expect(context.controller.selectedEnvironmentID == .rainyCabin)
        #expect(context.engine.fadeOutDurations == [8])
    }

    @Test("Selection changes notify the desktop atmosphere exactly once")
    func selectionCallback() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }
        var changes: [EnvironmentID] = []
        context.controller.onSelectionChanged = { changes.append($0) }

        context.controller.select(.sunsetDrive)
        context.controller.select(.sunsetDrive)
        context.controller.select(.train)

        #expect(changes == [.sunsetDrive, .train])
    }

    @Test("Sound off blocks playback and turning it back on never auto-starts")
    func soundGating() {
        let context = makeContext()
        defer { context.defaults.cleanUp() }

        #expect(context.controller.isSoundEnabled)

        context.controller.play()
        #expect(context.controller.state == .playing)
        #expect(context.engine.playCalls.count == 1)

        context.controller.setSoundEnabled(false)
        #expect(!context.controller.isSoundEnabled)
        #expect(!context.preferences.soundEnabled)
        #expect(context.controller.state == .paused)
        #expect(context.engine.fadeOutDurations == [context.preferences.fadeOutSeconds])

        context.controller.play()
        #expect(context.controller.state == .paused)
        #expect(context.engine.playCalls.count == 1)

        context.controller.setSoundEnabled(true)
        #expect(context.controller.isSoundEnabled)
        #expect(context.controller.state == .paused)
        #expect(context.engine.playCalls.count == 1)

        context.controller.play()
        #expect(context.controller.state == .playing)
        #expect(context.engine.playCalls.count == 2)
    }

    @Test("Launch resume respects the sound switch")
    func resumeRespectsSoundOff() {
        let off = makeContext { preferences in
            preferences.resumePlaybackOnLaunch = true
            preferences.soundEnabled = false
        }
        defer { off.defaults.cleanUp() }

        off.controller.restorePlaybackIfNeeded()

        #expect(off.controller.state == .idle)
        #expect(off.engine.playCalls.isEmpty)
    }

    @Test("Sound off while idle is harmless")
    func soundOffWhileIdle() {
        let context = makeContext { preferences in
            preferences.soundEnabled = false
        }
        defer { context.defaults.cleanUp() }

        context.controller.setSoundEnabled(false)
        #expect(context.controller.state == .idle)
        #expect(context.engine.fadeOutDurations.isEmpty)
        #expect(context.engine.playCalls.isEmpty)

        context.controller.togglePlayback()
        #expect(context.controller.state == .idle)
        #expect(context.engine.playCalls.isEmpty)
    }
}
