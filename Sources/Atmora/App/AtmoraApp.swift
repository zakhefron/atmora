import AppKit
import SwiftUI
import AtmoraCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = coordinator.preferences.theme.appearance
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("--asset-check") {
            runAssetCheck()
            return
        }

        if let index = arguments.firstIndex(of: "--ui-snapshot"),
           index + 1 < arguments.count {
            renderUISnapshot(to: arguments[index + 1])
            return
        }

        if let index = arguments.firstIndex(of: "--ui-snapshot-main"),
           index + 1 < arguments.count {
            renderMainSnapshot(to: arguments[index + 1])
            return
        }

        coordinator.start()

        if arguments.contains("--audio-smoke-test") {
            runAudioSmokeTest()
            return
        }

        if coordinator.preferences.launchBehavior == .mainWindow {
            coordinator.showMainWindow()
        }
    }

    /// Renders the menu-bar popover to a PNG without opening it. This exists so
    /// the README screenshot can be regenerated on machines where synthetic
    /// clicks are not permitted.
    private func renderUISnapshot(to path: String) {
        renderSnapshot(
            AnyView(MenuBarView().environment(coordinator)),
            size: NSSize(width: 336, height: 652),
            to: path
        )
    }

    /// Renders the main window off-screen at a height that fits the whole
    /// ambience rail, including the Atmosphere card. A normal window is
    /// constrained by the display, which would clip the Desktop controls.
    private func renderMainSnapshot(to path: String) {
        renderSnapshot(
            AnyView(MainWindowView().environment(coordinator)),
            size: NSSize(width: 1100, height: 1120),
            to: path
        )
    }

    private func renderSnapshot(_ rootView: AnyView, size: NSSize, to path: String) {
        NSApp.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hosting.layoutSubtreeIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                fputs("ATMORA_SNAPSHOT failed\n", stderr)
                exit(1)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: representation)

            guard let data = representation.representation(using: .png, properties: [:]) else {
                fputs("ATMORA_SNAPSHOT failed\n", stderr)
                exit(1)
            }

            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                fputs("ATMORA_SNAPSHOT failed=\(error.localizedDescription)\n", stderr)
                exit(1)
            }

            print("ATMORA_SNAPSHOT wrote=\(path) size=\(representation.pixelsWide)x\(representation.pixelsHigh)")
            exit(0)
        }
    }

    /// A non-interactive check used after installation. It proves that the
    /// bundle's audio, wallpapers, and icon resolve from the installed location
    /// rather than from the source tree.
    private func runAssetCheck() {
        NSApp.setActivationPolicy(.accessory)

        let bundle = Bundle.main
        let audioDirectory = AppResources.audioDirectory()
        let wallpaperDirectory = AppResources.wallpaperDirectory()
        let audioFiles = audioDirectory.map { files(in: $0, extension: "m4a") } ?? []
        let wallpaperFiles = wallpaperDirectory.map { files(in: $0, extension: "jpg") } ?? []
        let missingWallpapers = EnvironmentID.allCases.filter { AppResources.wallpaperURL(for: $0) == nil }
        let iconURL = bundle.url(forResource: "AppIcon", withExtension: "icns")
        let iconExists = iconURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        let expectedLayers = coordinator.catalog.environments.reduce(0) { $0 + $1.layers.count }
        let audioLayerFiles = audioFiles.filter { !$0.path.contains("/ui/") }
        let audioOK = audioLayerFiles.count == expectedLayers && coordinator.assetReport.isComplete
        let wallpapersOK = missingWallpapers.isEmpty && wallpaperFiles.count >= EnvironmentID.allCases.count
        let passed = audioOK && wallpapersOK && iconExists

        print("ATMORA_ASSETS bundle=\(bundle.bundlePath)")
        print("ATMORA_ASSETS bundle_id=\(bundle.bundleIdentifier ?? "missing")")
        print("ATMORA_ASSETS audio_dir=\(audioDirectory?.path ?? "missing") files=\(audioLayerFiles.count) complete=\(coordinator.assetReport.isComplete)")
        print("ATMORA_ASSETS wallpaper_dir=\(wallpaperDirectory?.path ?? "missing") files=\(wallpaperFiles.count) missing=\(missingWallpapers.map(\.rawValue).joined(separator: ","))")
        print("ATMORA_ASSETS icon=\(iconURL?.path ?? "missing") exists=\(iconExists)")
        print("ATMORA_ASSETS result=\(passed ? "ok" : "failed")")
        fflush(stdout)
        exit(passed ? 0 : 1)
    }

    private func files(in directory: URL, extension fileExtension: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var matches: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == fileExtension {
            matches.append(url)
        }
        return matches
    }

    /// A small, non-interactive diagnostic used by the release build check. It
    /// proves the real AVAudioEngine path loads buffers and starts, rather than
    /// only exercising the controller with a mock.
    private func runAudioSmokeTest() {
        NSApp.setActivationPolicy(.accessory)
        let initial = coordinator.playback.state

        coordinator.playback.play()
        let started = coordinator.playback.state == .playing

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else {
                print("ATMORA_SMOKE failed=missing-coordinator")
                exit(1)
            }

            let running = self.coordinator.audioEngine.isRunning
            let error = self.coordinator.playback.errorMessage ?? "none"
            let passed = started && running && self.coordinator.playback.state == .playing

            print("ATMORA_SMOKE started=\(started) initialState=\(initial.rawValue) engineRunning=\(running) state=\(self.coordinator.playback.state.rawValue) error=\(error)")

            self.coordinator.shutdown()
            fflush(stdout)
            exit(passed ? 0 : 1)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

@main
struct AtmoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.coordinator)
        } label: {
            Image(nsImage: MenuBarIcon.make())
                .accessibilityLabel("Atmora")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsPanel()
                .environment(appDelegate.coordinator)
        }

        .commands {
            AtmoraCommands(coordinator: appDelegate.coordinator)
        }
    }
}

struct AtmoraCommands: Commands {
    let coordinator: AppCoordinator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Atmora") {
                coordinator.showMainWindow()
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Playback") {
            Button(coordinator.playback.isPlaying ? "Pause" : "Play") {
                coordinator.playback.togglePlayback()
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button("Next Ambience") {
                coordinator.playback.selectNext()
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Previous Ambience") {
                coordinator.playback.selectPrevious()
            }
            .keyboardShortcut("[", modifiers: .command)

            Divider()

            ForEach(Array(coordinator.catalog.environments.enumerated()), id: \.element.id) { index, environment in
                Button(environment.name) {
                    coordinator.playback.select(environment.id)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }

            Divider()

            Button("Start \(FocusDuration.summary(for: coordinator.preferences.lastFocusMinutes)) Focus") {
                coordinator.startFocus(minutes: coordinator.preferences.lastFocusMinutes)
            }
            .disabled(coordinator.focusTimer.phase == .running)
        }
    }
}
