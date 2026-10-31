import AppKit
import Foundation
import AtmoraCore

/// Locates bundled assets both in the packaged `.app` and when running from
/// the Swift package during development. No user-specific paths are stored.
enum AppResources {
    static func audioDirectory() -> URL? {
        for candidate in candidates(named: "Audio") where isDirectory(candidate) {
            return candidate
        }
        return nil
    }

    static func wallpaperDirectory() -> URL? {
        for candidate in candidates(named: "Wallpapers") where isDirectory(candidate) {
            return candidate
        }
        return nil
    }

    static func wallpaperURL(for environment: EnvironmentID) -> URL? {
        guard let directory = wallpaperDirectory() else { return nil }
        let url = directory.appendingPathComponent("\(environment.rawValue).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func candidates(named name: String) -> [URL] {
        var urls: [URL] = []

        if let override = ProcessInfo.processInfo.environment["ATMORA_ASSETS_DIR"] {
            urls.append(URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(name))
        }
        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent(name))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources").appendingPathComponent(name))

        // Development fallbacks: the executable lives in .build/<arch>/<config>/.
        var executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<7 {
            urls.append(executableDirectory.appendingPathComponent("Assets/\(name)"))
            executableDirectory.deleteLastPathComponent()
        }

        // Compile-time source location, resolved rather than hard-coded.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // Atmora
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repository root
        urls.append(sourceRoot.appendingPathComponent("Assets/\(name)"))

        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/\(name)"))
        return urls
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?) where !short.isEmpty:
            return build.isEmpty ? short : "\(short) (\(build))"
        default:
            return "1.0.0 (development)"
        }
    }

    static var applicationIcon: NSImage? {
        if let icon = NSApplication.shared.applicationIconImage, icon.size.width > 32 {
            return icon
        }
        return nil
    }
}
