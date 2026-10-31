import AVFoundation
import Foundation

public struct AudioAssetReport: Sendable {
    public var available: Set<EnvironmentID>
    public var issues: [EnvironmentID: [String]]

    public init(available: Set<EnvironmentID>, issues: [EnvironmentID: [String]] = [:]) {
        self.available = available
        self.issues = issues
    }

    public var isComplete: Bool {
        issues.isEmpty && available.count == EnvironmentID.allCases.count
    }

    public func message(for environment: EnvironmentID) -> String? {
        guard let entries = issues[environment], !entries.isEmpty else { return nil }
        return entries.joined(separator: " ")
    }

    public static func allAvailable() -> AudioAssetReport {
        AudioAssetReport(available: Set(EnvironmentID.allCases))
    }
}

/// Lightweight, metadata-only validation of the bundled sound layers. It opens
/// each file but does not keep it in memory, so it is cheap enough to run at
/// launch. Full playback failures are still handled by the audio engine.
public enum AudioAssetValidator {
    public static func validate(
        catalog: EnvironmentCatalog,
        audioDirectory: URL
    ) -> AudioAssetReport {
        var available: Set<EnvironmentID> = []
        var issues: [EnvironmentID: [String]] = [:]

        for environment in catalog.environments {
            var environmentIssues: [String] = []
            for layer in environment.layers {
                let url = audioDirectory.appendingPathComponent(layer.fileName)
                environmentIssues.append(contentsOf: inspect(url: url, layer: layer))
            }
            if environmentIssues.isEmpty {
                available.insert(environment.id)
            } else {
                issues[environment.id] = environmentIssues
            }
        }

        return AudioAssetReport(available: available, issues: issues)
    }

    public static func inspect(url: URL, layer: SoundLayer) -> [String] {
        var problems: [String] = []
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return ["\(layer.name): the audio file is missing."]
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let seconds = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
            if file.length <= 0 {
                problems.append("\(layer.name): the audio file is empty.")
            }
            if format.channelCount == 0 || format.sampleRate < 22_000 {
                problems.append("\(layer.name): the audio format is unsupported.")
            }
            if seconds < 10 || seconds > 180 {
                problems.append("\(layer.name): the audio loop has an unexpected length.")
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int ?? 0
            if size < 1_000 {
                problems.append("\(layer.name): the audio file looks damaged.")
            }
        } catch {
            problems.append("\(layer.name): the audio file could not be read.")
        }
        return problems
    }

    /// Decodes a short segment and reports its peak amplitude. Used by tests to
    /// prove a bundled layer actually contains sound rather than digital silence.
    public static func peakAmplitude(url: URL, seconds: TimeInterval = 3) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(min(Double(file.length), format.sampleRate * seconds))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return 0
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(samples[frame]))
            }
        }
        return peak
    }
}
