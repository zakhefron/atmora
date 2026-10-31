import Foundation
import Testing
@testable import AtmoraCore

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    @Test("Defaults are calm and safe")
    func defaults() {
        let settings = AtmoraSettings()

        #expect(settings.theme == .system)
        #expect(settings.launchBehavior == .mainWindow)
        #expect(!settings.launchAtLogin)
        #expect(settings.shortcutEnabled)
        #expect(settings.shortcut == .default)
        #expect(settings.animationEnabled)
        #expect(settings.density == .comfortable)
        #expect(!settings.resumePlaybackOnLaunch)
        #expect(!settings.notificationsEnabled)
        #expect(settings.stopAudioWhenTimerEnds)
        #expect(settings.lastEnvironment == .rainyCabin)
        #expect(abs(settings.fadeInSeconds - 1.6) < 0.0001)
        #expect(abs(settings.fadeOutSeconds - 1.2) < 0.0001)
        #expect(settings.timerSnapshot == nil)
        #expect(settings.soundEnabled)
        #expect(settings.desktopMode == .livingDesktop)
        #expect(settings.lastFocusMinutes == FocusDuration.defaultMinutes)
    }

    @Test("Settings round-trip through JSON")
    func roundTrip() throws {
        var settings = AtmoraSettings()
        settings.theme = .dark
        settings.launchBehavior = .menuBar
        settings.density = .compact
        settings.lastEnvironment = .seasideRecords
        settings.fadeInSeconds = 3.2
        settings.soundEnabled = false
        settings.desktopMode = .livingDesktop
        settings.savedMixes["seaside-records"] = SavedMix(
            levels: ["waves": 0.42],
            muted: ["piano"],
            savedAt: Date(timeIntervalSinceReferenceDate: 1000)
        )
        settings.timerSnapshot = FocusTimerSnapshot(
            phase: .paused,
            endDate: nil,
            remaining: 600,
            duration: 1500
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AtmoraSettings.self, from: data)

        #expect(decoded == settings)
    }

    @Test("Corrupt preferences fall back and are preserved for diagnosis")
    func corruptPreferences() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let key = "atmora.settings.v1"
        let payload = Data("this is not json".utf8)
        harness.defaults.set(payload, forKey: key)

        let store = harness.makeStore(storageKey: key)

        #expect(store.loadIssue != nil)
        #expect(store.theme == .system)
        #expect(store.lastEnvironment == .rainyCabin)
        #expect(harness.defaults.data(forKey: key + ".unreadable") == payload)
    }

    @Test("Normalization clamps every value into a safe range")
    func normalization() {
        var settings = AtmoraSettings()
        settings.startupVolume = 5
        settings.lastMasterVolume = -2
        settings.fadeInSeconds = 99
        settings.fadeOutSeconds = -4
        settings.lastFocusMinutes = 1000
        settings.shortcut = KeyCombo(keyCode: 1, key: "", modifiers: [])
        settings.savedMixes["rainy-cabin"] = SavedMix(levels: ["rain": 4, "thunder": -1])

        settings.normalize()

        #expect(settings.startupVolume == 1)
        #expect(settings.lastMasterVolume == 0)
        #expect(settings.fadeInSeconds == 8)
        #expect(settings.fadeOutSeconds == 0)
        #expect(settings.lastFocusMinutes == 240)
        #expect(settings.shortcut == .default)
        #expect(settings.savedMixes["rainy-cabin"]?.levels["rain"] == 1)
        #expect(settings.savedMixes["rainy-cabin"]?.levels["thunder"] == 0)
    }

    @Test("Preferences persist after flush and reload")
    func persistence() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let key = "prefs-test"

        let first = harness.makeStore(storageKey: key)
        first.theme = .light
        first.launchBehavior = .menuBar
        first.fadeInSeconds = 2.5
        first.lastEnvironment = .rainyCabin
        first.flush()

        let second = harness.makeStore(storageKey: key)
        #expect(second.theme == .light)
        #expect(second.launchBehavior == .menuBar)
        #expect(abs(second.fadeInSeconds - 2.5) < 0.0001)
        #expect(second.lastEnvironment == .rainyCabin)
    }

    @Test("Theme and shortcut changes notify the app exactly when needed")
    func changeCallbacks() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let store = harness.makeStore()
        var themeCallbacks: [ThemePreference] = []
        var shortcutCallbacks = 0
        store.onThemeChanged = { themeCallbacks.append($0) }
        store.onShortcutChanged = { shortcutCallbacks += 1 }

        store.theme = .dark
        store.theme = .dark
        store.shortcut = KeyCombo(keyCode: 0, key: "A", modifiers: [.control, .option])
        store.shortcutEnabled = false

        #expect(themeCallbacks == [.dark])
        #expect(shortcutCallbacks == 2)
        #expect(store.shortcut?.display == "⌃⌥A")
    }

    @Test("Invalid shortcuts are rejected at the store boundary")
    func invalidShortcut() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let store = harness.makeStore()

        store.shortcut = KeyCombo(keyCode: 12, key: "Q", modifiers: [.shift])
        #expect(store.shortcut == nil)

        store.shortcut = KeyCombo(keyCode: 12, key: "", modifiers: [.command])
        #expect(store.shortcut == nil)

        store.shortcut = KeyCombo(keyCode: 12, key: "Q", modifiers: [.option, .command])
        #expect(store.shortcut == .default)
    }

    @Test("Saved mixes can be saved, read, and cleared")
    func savedMixes() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let store = harness.makeStore()
        let mix = SavedMix(levels: ["rain": 0.5, "fireplace": 0.3], muted: ["thunder"])

        #expect(!store.hasSavedMix(for: .rainyCabin))
        store.saveMix(mix, for: .rainyCabin)
        #expect(store.hasSavedMix(for: .rainyCabin))
        #expect(store.savedMix(for: .rainyCabin) == mix)

        store.clearMix(for: .rainyCabin)
        #expect(!store.hasSavedMix(for: .rainyCabin))
        #expect(store.savedMix(for: .rainyCabin) == nil)
    }

    @Test("Key combinations display and validate correctly")
    func keyCombos() {
        #expect(KeyCombo.default.display == "⌥⌘Q")
        #expect(KeyCombo.default.isValid)

        let shiftOnly = KeyCombo(keyCode: 1, key: "S", modifiers: [.shift])
        #expect(!shiftOnly.isValid)

        let controlOption = KeyCombo(keyCode: 1, key: "S", modifiers: [.control, .option])
        #expect(controlOption.display == "⌃⌥S")
        #expect(controlOption.isValid)
    }

    @Test("The compact layout alias stays in sync with density")
    func compactAlias() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let store = harness.makeStore()

        store.compactLayout = true
        #expect(store.density == .compact)
        #expect(store.compactLayout)

        store.compactLayout = false
        #expect(store.density == .comfortable)
        #expect(!store.compactLayout)

        store.density = .compact
        #expect(store.compactLayout)
    }

    @Test("Timer preferences and snapshots persist")
    func timerPreferences() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let key = "timer-prefs"

        let first = harness.makeStore(storageKey: key)
        first.lastFocusMinutes = 50
        first.stopAudioWhenTimerEnds = false
        first.timerSnapshot = FocusTimerSnapshot(
            phase: .running,
            endDate: Date(timeIntervalSinceReferenceDate: 5000),
            remaining: 1200,
            duration: 1500
        )
        first.flush()

        let second = harness.makeStore(storageKey: key)
        #expect(second.lastFocusMinutes == 50)
        #expect(!second.stopAudioWhenTimerEnds)
        #expect(second.timerSnapshot?.phase == .running)
        #expect(second.timerSnapshot?.endDate == Date(timeIntervalSinceReferenceDate: 5000))
        #expect(second.timerSnapshot?.remaining == 1200)
    }

    @Test("Focus duration snaps and clamps at the store boundary")
    func focusDurationBoundary() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let store = harness.makeStore()

        store.lastFocusMinutes = 7
        #expect(store.lastFocusMinutes == 5)

        store.lastFocusMinutes = 53
        #expect(store.lastFocusMinutes == 55)

        store.lastFocusMinutes = 10_000
        #expect(store.lastFocusMinutes == 240)

        store.lastFocusMinutes = -10
        #expect(store.lastFocusMinutes == 5)
    }

    @Test("Sound and desktop switches persist across launches")
    func atmospherePersistence() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let key = "atmosphere-prefs"

        let first = harness.makeStore(storageKey: key)
        first.soundEnabled = false
        first.desktopMode = .appOnly
        first.flush()

        let second = harness.makeStore(storageKey: key)
        #expect(!second.soundEnabled)
        #expect(second.desktopMode == .appOnly)

        second.soundEnabled = true
        second.desktopMode = .livingDesktop
        second.flush()

        let third = harness.makeStore(storageKey: key)
        #expect(third.soundEnabled)
        #expect(third.desktopMode == .livingDesktop)
    }

    @Test("Saved mix levels are clamped when loaded")
    func clampedMixLevels() throws {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let key = "clamped-mix"

        var settings = AtmoraSettings()
        settings.savedMixes["rainy-cabin"] = SavedMix(levels: ["rain": 9, "fireplace": -3])
        let data = try JSONEncoder().encode(settings)
        harness.defaults.set(data, forKey: key)

        let store = harness.makeStore(storageKey: key)
        #expect(store.savedMix(for: .rainyCabin)?.levels["rain"] == 1)
        #expect(store.savedMix(for: .rainyCabin)?.levels["fireplace"] == 0)
    }
}
