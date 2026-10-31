import AVFoundation
import Foundation
import ImageIO
import Testing
@testable import AtmoraCore

@Suite("Bundled audio", .serialized)
struct AssetTests {
    private let catalog = EnvironmentCatalog.standard

    private var audioRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AtmoraCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Assets/Audio", isDirectory: true)
    }

    @Test("The validator accepts every bundled environment")
    func validatorFindsEveryEnvironment() {
        let report = AudioAssetValidator.validate(catalog: catalog, audioDirectory: audioRoot)
        let detail = report.issues.mapValues { $0.joined(separator: " ") }
        #expect(report.isComplete, "Audio validation issues: \(detail)")
        #expect(report.available == Set(EnvironmentID.allCases))
    }

    @Test("Every layer is exactly 40 seconds of 32 kHz stereo AAC")
    func expectedFormatAndLength() throws {
        for environment in catalog.environments {
            for layer in environment.layers {
                let url = audioRoot.appendingPathComponent(layer.fileName)
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat

                #expect(abs(format.sampleRate - 32_000) < 0.01, "\(layer.fileName)")
                #expect(format.channelCount == 2, "\(layer.fileName)")
                #expect(file.length == 1_280_000, "\(layer.fileName) should be exactly 40 seconds")
                #expect(abs(Double(file.length) / format.sampleRate - 40.0) < 0.0001)
            }
        }
    }

    @Test("Every layer has sound and no discontinuity at the loop seam")
    func audibleAndClickFree() throws {
        for environment in catalog.environments {
            for layer in environment.layers {
                let url = audioRoot.appendingPathComponent(layer.fileName)
                let samples = try readAllSamples(from: url)

                var peak: Float = 0
                var seamJump: Float = 0
                var largestOrdinaryJump: Float = 0

                for channel in samples {
                    for value in channel {
                        peak = max(peak, abs(value))
                    }

                    guard channel.count > 2 else { continue }
                    seamJump = max(seamJump, abs(channel[0] - channel[channel.count - 1]))
                    for index in 1..<channel.count {
                        largestOrdinaryJump = max(largestOrdinaryJump, abs(channel[index] - channel[index - 1]))
                    }
                }

                #expect(peak > 0.02, "\(layer.fileName) is silent or nearly silent")
                #expect(
                    seamJump <= largestOrdinaryJump + 0.0001,
                    "\(layer.fileName) jumps at the loop seam (\(seamJump) > \(largestOrdinaryJump))"
                )
            }
        }
    }

    @Test("The manifest describes every shipped file")
    func manifestMatchesCatalogue() throws {
        let manifestURL = audioRoot.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        #expect(manifest.sampleRate == 32_000)
        #expect(manifest.channels == 2)
        #expect(abs(manifest.loopSeconds - 40.0) < 0.001)
        #expect(!manifest.license.isEmpty)
        #expect(manifest.layers.count == 19)
        let manifestFiles = Set(manifest.layers.map(\.file)).filter { !$0.hasPrefix("ui/") }
        #expect(manifestFiles == Set(catalog.allLayerFileNames))

        for entry in manifest.layers {
            #expect(entry.peakDBFS > -40)
            #expect(entry.peakDBFS < 0)
        }
    }

    @Test("Every environment has a matching 4K JPEG wallpaper")
    func wallpapersMatchCatalogue() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Assets/Wallpapers", isDirectory: true)

        let shipped = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
        #expect(shipped.count == EnvironmentID.allCases.count)

        for id in EnvironmentID.allCases {
            let url = root.appendingPathComponent("\(id.rawValue).jpg")
            #expect(FileManager.default.fileExists(atPath: url.path), "\(id.rawValue) wallpaper is missing")

            let source = try #require(
                CGImageSourceCreateWithURL(url as CFURL, nil),
                "\(id.rawValue) wallpaper is unreadable"
            )
            #expect(CGImageSourceGetType(source) as String? == "public.jpeg")

            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            #expect(properties?[kCGImagePropertyPixelWidth] as? Int == 3840, "\(id.rawValue) width")
            #expect(properties?[kCGImagePropertyPixelHeight] as? Int == 2160, "\(id.rawValue) height")
        }
    }

    // MARK: - Helpers

    private func readAllSamples(from url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let frames = Int(buffer.frameLength)
        return (0..<Int(format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: frames))
        }
    }

    private struct Manifest: Decodable {
        var sampleRate: Int
        var channels: Int
        var loopSeconds: Double
        var license: String
        var layers: [Layer]

        enum CodingKeys: String, CodingKey {
            case sampleRate = "sample_rate"
            case channels
            case loopSeconds = "loop_seconds"
            case license
            case layers
        }

        struct Layer: Decodable {
            var file: String
            var peakDBFS: Double

            enum CodingKeys: String, CodingKey {
                case file
                case peakDBFS = "peak_dbfs"
            }
        }
    }
}
