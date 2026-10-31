import AVFoundation
import Foundation
import AtmoraCore

/// Owns Atmora's audio graph. Audio layers are decoded into memory only while
/// they are needed; pausing or leaving an environment releases them.
@MainActor
final class AudioEngineManager: AudioPlaybackEngine {
    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()
    private let audioDirectory: URL?
    private var groups: [PlaybackGroup] = []

    private var masterVolume: Double = 0.7
    private var masterUserRamp = GainRamp(0)
    private var masterEnvelope = GainRamp(0)
    private var fadeTimer: Timer?
    private var configurationObserver: NSObjectProtocol?
    private var lastLevels: [String: Double] = [:]
    private var currentEnvironment: SoundEnvironment?
    private var isHandlingConfigurationChange = false
    private var wantsPlayback = false

    /// Fixed headroom so three restrained layers can never approach clipping at
    /// full volume, without relying on compression.
    private let headroom: Float = 0.88

    /// Dedicated player for UI click sounds (environment changes).
    private var clickPlayer: AVAudioPlayer?

    var onRuntimeFailure: ((String) -> Void)?

    private(set) var lastError: String?

    init(audioDirectory: URL?) {
        self.audioDirectory = audioDirectory

        // Preload the UI click sound.
        if let audioDirectory {
            let clickURL = audioDirectory.appendingPathComponent("ui/click.m4a")
            clickPlayer = try? AVAudioPlayer(contentsOf: clickURL)
            clickPlayer?.volume = 0.7
            clickPlayer?.prepareToPlay()
        }

        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 1
        masterMixer.outputVolume = 0

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
    }

    deinit {
        fadeTimer?.invalidate()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        if engine.isRunning {
            engine.stop()
        }
    }

    var isRunning: Bool {
        !groups.isEmpty
    }

    // MARK: - AudioPlaybackEngine

    func play(
        environment: SoundEnvironment,
        levels: [String: Double],
        masterVolume: Double,
        fadeIn: TimeInterval
    ) throws {
        let now = ProcessInfo.processInfo.systemUptime
        self.masterVolume = min(max(masterVolume, 0), 1)
        lastLevels = levels
        currentEnvironment = environment
        wantsPlayback = true

        if groups.isEmpty {
            masterUserRamp.snap(volumeAmplitude(self.masterVolume))
        } else {
            masterUserRamp.ramp(to: volumeAmplitude(self.masterVolume), duration: 0.12, at: now)
        }

        let group = try makeGroup(environment: environment, levels: levels, initialGain: 1)
        groups.append(group)

        // Anything left over from a previous fade becomes an outgoing group.
        for existing in groups where existing !== group {
            existing.shouldRemove = true
            existing.gain.ramp(to: 0, duration: min(max(fadeIn, 0.35), 0.7), at: now)
        }

        masterEnvelope.ramp(to: 1, duration: max(fadeIn, 0.15), at: now)
        startFadeTimer()
    }

    func crossfade(
        to environment: SoundEnvironment,
        levels: [String: Double],
        duration: TimeInterval
    ) throws {
        guard !groups.isEmpty else {
            try play(
                environment: environment,
                levels: levels,
                masterVolume: masterVolume,
                fadeIn: max(duration, 0.4)
            )
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let group = try makeGroup(environment: environment, levels: levels, initialGain: 0)
        groups.append(group)
        currentEnvironment = environment
        lastLevels = levels
        wantsPlayback = true

        for existing in groups where existing !== group {
            existing.shouldRemove = true
            let existingFade = existing.gain.current < 0.001 ? 0.2 : max(duration, 0.35)
            existing.gain.ramp(to: 0, duration: existingFade, at: now)
        }
        group.gain.ramp(to: 1, duration: max(duration, 0.35), at: now)
        startFadeTimer()
    }

    func applyLevels(_ levels: [String: Double], for environment: EnvironmentID) {
        guard currentEnvironment?.id == environment else { return }
        lastLevels = levels
        let now = ProcessInfo.processInfo.systemUptime
        for group in groups where group.environment.id == environment && !group.shouldRemove {
            for layer in group.environment.layers {
                guard let chain = group.layers[layer.id] else { continue }
                let target = Float(min(max(levels[layer.id] ?? 0, 0), 1))
                chain.gain.ramp(to: target, duration: 0.1, at: now)
            }
        }
        startFadeTimer()
    }

    func setMasterVolume(_ volume: Double) {
        masterVolume = min(max(volume, 0), 1)
        let target = volumeAmplitude(masterVolume)
        let now = ProcessInfo.processInfo.systemUptime
        if groups.isEmpty {
            masterUserRamp.snap(target)
            masterMixer.outputVolume = target * masterEnvelope.current * headroom
        } else {
            masterUserRamp.ramp(to: target, duration: 0.12, at: now)
            startFadeTimer()
        }
    }

    func fadeOutAndStop(duration: TimeInterval) {
        wantsPlayback = false
        let now = ProcessInfo.processInfo.systemUptime
        let fade = max(duration, 0.08)
        masterEnvelope.ramp(to: 0, duration: fade, at: now)
        for group in groups {
            group.shouldRemove = true
            group.gain.ramp(to: 0, duration: fade, at: now)
        }
        startFadeTimer()
    }

    func stopImmediately() {
        wantsPlayback = false
        fadeTimer?.invalidate()
        fadeTimer = nil
        teardownAllGroups()
        if engine.isRunning {
            engine.stop()
        }
        masterEnvelope.snap(0)
        masterMixer.outputVolume = 0
    }

    func playClick() {
        guard let clickPlayer else { return }
        if clickPlayer.isPlaying {
            clickPlayer.currentTime = 0
        }
        clickPlayer.play()
    }

    func shutdown() {
        stopImmediately()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    // MARK: - Graph

    private func makeGroup(
        environment: SoundEnvironment,
        levels: [String: Double],
        initialGain: Float
    ) throws -> PlaybackGroup {
        guard let audioDirectory else {
            throw AudioEngineError.assetsUnavailable(environment.name)
        }

        // Decode everything before touching the graph so a missing file cannot
        // leave a half-attached environment behind.
        var decoded: [(layer: SoundLayer, buffer: AVAudioPCMBuffer)] = []
        for layer in environment.layers {
            let url = audioDirectory.appendingPathComponent(layer.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AudioEngineError.missingFile(layer, environment)
            }
            do {
                let file = try AVAudioFile(forReading: url)
                guard file.length > 0,
                      let buffer = AVAudioPCMBuffer(
                          pcmFormat: file.processingFormat,
                          frameCapacity: AVAudioFrameCount(file.length)
                      ) else {
                    throw AudioEngineError.unreadableFile(layer, environment)
                }
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else {
                    throw AudioEngineError.unreadableFile(layer, environment)
                }
                decoded.append((layer, buffer))
            } catch let error as AudioEngineError {
                throw error
            } catch {
                throw AudioEngineError.unreadableFile(layer, environment)
            }
        }

        guard let referenceFormat = decoded.first?.buffer.format else {
            throw AudioEngineError.assetsUnavailable(environment.name)
        }

        let group = PlaybackGroup(environment: environment, initialGain: initialGain)

        engine.attach(group.mixer)
        do {
            engine.connect(group.mixer, to: masterMixer, format: referenceFormat)

            for entry in decoded {
                let player = AVAudioPlayerNode()
                let layerMixer = AVAudioMixerNode()
                engine.attach(player)
                engine.attach(layerMixer)
                engine.connect(player, to: layerMixer, format: entry.buffer.format)
                engine.connect(layerMixer, to: group.mixer, format: entry.buffer.format)

                let target = Float(min(max(levels[entry.layer.id] ?? 0, 0), 1))
                layerMixer.outputVolume = target
                player.scheduleBuffer(entry.buffer, at: nil, options: .loops)

                group.layers[entry.layer.id] = LayerChain(
                    player: player,
                    mixer: layerMixer,
                    buffer: entry.buffer,
                    gain: GainRamp(target)
                )
            }

            if !engine.isRunning {
                engine.prepare()
                do {
                    try engine.start()
                } catch {
                    throw AudioEngineError.engineStart
                }
            }

            for chain in group.layers.values {
                chain.player.play()
            }
            group.mixer.outputVolume = initialGain
            lastError = nil
            return group
        } catch {
            teardown(group: group)
            if let audioError = error as? AudioEngineError {
                throw audioError
            }
            throw AudioEngineError.engineStart
        }
    }

    private func teardown(group: PlaybackGroup) {
        for chain in group.layers.values {
            chain.player.stop()
            chain.player.reset()
        }
        engine.disconnectNodeOutput(group.mixer)
        for chain in group.layers.values {
            engine.disconnectNodeOutput(chain.mixer)
            engine.disconnectNodeOutput(chain.player)
            engine.detach(chain.mixer)
            engine.detach(chain.player)
        }
        engine.detach(group.mixer)
        group.layers.removeAll()
    }

    private func teardownAllGroups() {
        for group in groups {
            teardown(group: group)
        }
        groups.removeAll()
    }

    // MARK: - Fades

    private struct GainRamp {
        private(set) var current: Float
        private var from: Float
        private var to: Float
        private var start: TimeInterval
        private var duration: TimeInterval
        private(set) var isActive: Bool

        init(_ value: Float) {
            current = value
            from = value
            to = value
            start = 0
            duration = 0
            isActive = false
        }

        mutating func snap(_ value: Float) {
            current = value
            from = value
            to = value
            isActive = false
        }

        mutating func ramp(to target: Float, duration: TimeInterval, at now: TimeInterval) {
            let target = min(max(target, 0), 1)
            from = current
            to = target
            start = now
            self.duration = max(duration, 0.001)
            isActive = abs(target - current) > 0.0001
            if !isActive {
                current = target
            }
        }

        @discardableResult
        mutating func update(at now: TimeInterval) -> Float {
            guard isActive else { return current }
            let progress = min(max((now - start) / duration, 0), 1)
            let eased = Float(progress * progress * (3 - 2 * progress))
            current = from + (to - from) * eased
            if progress >= 1 {
                current = to
                isActive = false
            }
            return current
        }
    }

    private final class LayerChain {
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        let buffer: AVAudioPCMBuffer
        var gain: GainRamp

        init(player: AVAudioPlayerNode, mixer: AVAudioMixerNode, buffer: AVAudioPCMBuffer, gain: GainRamp) {
            self.player = player
            self.mixer = mixer
            self.buffer = buffer
            self.gain = gain
        }
    }

    private final class PlaybackGroup {
        let environment: SoundEnvironment
        let mixer = AVAudioMixerNode()
        var layers: [String: LayerChain] = [:]
        var gain: GainRamp
        var shouldRemove = false

        init(environment: SoundEnvironment, initialGain: Float) {
            self.environment = environment
            self.gain = GainRamp(initialGain)
        }
    }

    private func startFadeTimer() {
        guard fadeTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        var active = false

        let user = masterUserRamp.update(at: now)
        active = active || masterUserRamp.isActive
        let envelope = masterEnvelope.update(at: now)
        active = active || masterEnvelope.isActive
        masterMixer.outputVolume = user * envelope * headroom

        for group in groups {
            let gain = group.gain.update(at: now)
            active = active || group.gain.isActive
            group.mixer.outputVolume = gain

            for chain in group.layers.values {
                let layerGain = chain.gain.update(at: now)
                active = active || chain.gain.isActive
                chain.mixer.outputVolume = layerGain
            }
        }

        let finished = groups.filter { $0.shouldRemove && !$0.gain.isActive && $0.gain.current <= 0.0005 }
        for group in finished {
            teardown(group: group)
            groups.removeAll { $0 === group }
        }

        if groups.isEmpty {
            if engine.isRunning {
                engine.stop()
            }
            masterEnvelope.snap(0)
            masterMixer.outputVolume = 0
            active = false
        }

        if !active {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    private func volumeAmplitude(_ sliderValue: Double) -> Float {
        // Slightly perceptual, so the top of the slider is still useful without
        // making 50% inaudible.
        Float(pow(min(max(sliderValue, 0), 1), 1.28))
    }

    // MARK: - Device changes

    private func handleConfigurationChange() {
        guard !isHandlingConfigurationChange else { return }
        isHandlingConfigurationChange = true
        defer { isHandlingConfigurationChange = false }

        let wasPlaying = wantsPlayback && !groups.isEmpty
        let environment = currentEnvironment
        let levels = lastLevels
        let userAmplitude = masterUserRamp.current > 0 ? masterUserRamp.current : volumeAmplitude(masterVolume)

        teardownAllGroups()
        if engine.isRunning {
            engine.stop()
        }
        masterEnvelope.snap(0)
        masterMixer.outputVolume = 0

        engine.disconnectNodeOutput(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)

        guard wasPlaying, let environment else {
            return
        }

        do {
            let group = try makeGroup(environment: environment, levels: levels, initialGain: 1)
            groups.append(group)
            masterUserRamp.snap(userAmplitude)
            masterEnvelope.ramp(to: 1, duration: 0.6, at: ProcessInfo.processInfo.systemUptime)
            startFadeTimer()
        } catch {
            lastError = "Audio output changed and playback could not resume."
            onRuntimeFailure?("Audio output changed and Atmora could not resume playback. Press play to try again.")
        }
    }
}

enum AudioEngineError: LocalizedError {
    case assetsUnavailable(String)
    case missingFile(SoundLayer, SoundEnvironment)
    case unreadableFile(SoundLayer, SoundEnvironment)
    case engineStart

    var errorDescription: String? {
        switch self {
        case .assetsUnavailable(let name):
            return "The bundled audio for \(name) is unavailable."
        case .missingFile(let layer, let environment):
            return "\(layer.name) is missing from \(environment.name)."
        case .unreadableFile(let layer, let environment):
            return "\(layer.name) in \(environment.name) could not be read."
        case .engineStart:
            return "The audio system could not be started. Check your output device and try again."
        }
    }
}
