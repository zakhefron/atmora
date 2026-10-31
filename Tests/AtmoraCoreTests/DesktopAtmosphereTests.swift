import Foundation
import Testing
@testable import AtmoraCore

@MainActor
@Suite("Desktop atmosphere")
struct DesktopAtmosphereTests {
    @Test("A fresh install follows the room with a Living Desktop preview")
    func defaults() {
        let settings = AtmoraSettings()

        #expect(settings.desktopMode == .livingDesktop)
        #expect(settings.desktopFollowsEnvironment)
        #expect(settings.desktopAnimationEnabled)
        #expect(settings.desktopAnimationIntensity == .balanced)
        #expect(settings.desktopEffects == .standard)
        #expect(settings.desktopEffects.motionEnabled)
        #expect(settings.desktopEffects.bloomEnabled)
        #expect(settings.desktopEffects.particlesEnabled)
        #expect(settings.desktopDisplay == .allDisplays)
        #expect(settings.desktopAppliedEnvironment == nil)
        #expect(settings.desktopOriginalWallpapers.isEmpty)
    }

    @Test("App Only never writes the wallpaper, even when forced")
    func appOnlyNeverApplies() {
        #expect(!DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .appOnly,
            followsEnvironment: true,
            appliedEnvironment: nil,
            selectedEnvironment: .sunsetDrive,
            force: true
        ))
    }

    @Test("Wallpaper synchronization follows the selected environment")
    func followsEnvironment() {
        #expect(DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: true,
            appliedEnvironment: nil,
            selectedEnvironment: .sunsetDrive
        ))
        #expect(!DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: true,
            appliedEnvironment: .sunsetDrive,
            selectedEnvironment: .sunsetDrive
        ))
        #expect(DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: true,
            appliedEnvironment: .sunsetDrive,
            selectedEnvironment: .seasideRecords
        ))
    }

    @Test("With following disabled, the wallpaper is set once and then left alone")
    func doesNotFollowWhenDisabled() {
        #expect(DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: false,
            appliedEnvironment: nil,
            selectedEnvironment: .sunsetDrive
        ))
        #expect(!DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: false,
            appliedEnvironment: .sunsetDrive,
            selectedEnvironment: .rainyCabin
        ))
        #expect(DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: false,
            appliedEnvironment: .sunsetDrive,
            selectedEnvironment: .rainyCabin,
            force: true
        ))
    }

    @Test("Living Desktop uses the same wallpaper policy")
    func livingDesktopPolicy() {
        #expect(DesktopAtmospherePolicy.shouldApplyWallpaper(
            mode: .livingDesktop,
            followsEnvironment: true,
            appliedEnvironment: nil,
            selectedEnvironment: .rainyCabin
        ))
    }

    @Test("Display updates keep the applied environment when following is off")
    func environmentForDisplayUpdate() {
        #expect(DesktopAtmospherePolicy.environmentForUpdate(
            followsEnvironment: true,
            appliedEnvironment: .sunsetDrive,
            selectedEnvironment: .rainyCabin
        ) == .rainyCabin)

        #expect(DesktopAtmospherePolicy.environmentForUpdate(
            followsEnvironment: false,
            appliedEnvironment: .sunsetDrive,
            selectedEnvironment: .rainyCabin
        ) == .sunsetDrive)

        #expect(DesktopAtmospherePolicy.environmentForUpdate(
            followsEnvironment: false,
            appliedEnvironment: nil,
            selectedEnvironment: .rainyCabin
        ) == .rainyCabin)
    }

    @Test("Display selections normalize and survive JSON")
    func displaySelection() throws {
        var broken = DesktopDisplaySelection(scope: .specific, displayUUID: "")
        broken.normalize()
        #expect(broken == .allDisplays)

        var all = DesktopDisplaySelection(scope: .all, displayUUID: "ABC")
        all.normalize()
        #expect(all.displayUUID == nil)

        let specific = DesktopDisplaySelection.specific("display-uuid")
        let data = try JSONEncoder().encode(specific)
        let decoded = try JSONDecoder().decode(DesktopDisplaySelection.self, from: data)
        #expect(decoded == specific)
        #expect(decoded.isValid)
    }

    @Test("Original wallpaper records are honest about what can be restored")
    func originalWallpaperRestorability() throws {
        let missing = OriginalWallpaper(urlPath: "/definitely/not/here.jpg")
        #expect(!missing.isRestorable)

        let dynamic = OriginalWallpaper(urlPath: nil)
        #expect(!dynamic.isRestorable)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atmora-wallpaper-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let restorable = OriginalWallpaper(urlPath: url.path, imageScalingRawValue: 3, allowsClipping: true)
        #expect(restorable.isRestorable)
    }

    @Test("Desktop settings round-trip through JSON")
    func settingsRoundTrip() throws {
        var settings = AtmoraSettings()
        settings.desktopMode = .livingDesktop
        settings.desktopFollowsEnvironment = false
        settings.desktopAnimationEnabled = false
        settings.desktopAnimationIntensity = .immersive
        settings.desktopEffects = DesktopEffects(
            motionEnabled: false,
            bloomEnabled: true,
            particlesEnabled: false,
            intensity: 0.35
        )
        settings.desktopDisplay = .specific("ABC-123")
        settings.desktopAppliedEnvironment = .sunsetDrive
        settings.desktopOriginalWallpapers["ABC-123"] = OriginalWallpaper(
            urlPath: "/Users/example/Pictures/original.jpg",
            imageScalingRawValue: 2,
            allowsClipping: false,
            capturedAt: Date(timeIntervalSinceReferenceDate: 1234)
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AtmoraSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("Desktop effect intensity is clamped to a usable range")
    func effectsNormalize() {
        var effects = DesktopEffects(intensity: 2.4)
        #expect(effects.normalized.intensity == 1)

        effects.intensity = -0.5
        #expect(effects.normalized.intensity == 0)
    }

    @Test("Older settings without desktop keys still decode")
    func backwardsCompatible() throws {
        let json = """
        {"version":1,"theme":"dark","lastEnvironment":"sunset-drive"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AtmoraSettings.self, from: json)

        #expect(decoded.theme == .dark)
        #expect(decoded.lastEnvironment == .sunsetDrive)
        #expect(decoded.desktopMode == .livingDesktop)
        #expect(decoded.soundEnabled)
        #expect(decoded.lastFocusMinutes == FocusDuration.defaultMinutes)
        #expect(decoded.desktopDisplay == .allDisplays)
        #expect(decoded.desktopOriginalWallpapers.isEmpty)
    }

    @Test("App Only normalization clears the applied marker but keeps originals for a later restore")
    func normalization() {
        var settings = AtmoraSettings()
        settings.desktopMode = .appOnly
        settings.desktopAppliedEnvironment = .sunsetDrive
        settings.desktopDisplay = .specific("")
        settings.desktopOriginalWallpapers["display"] = OriginalWallpaper(urlPath: "/tmp/original.jpg")
        settings.normalize()

        #expect(settings.desktopAppliedEnvironment == nil)
        #expect(settings.desktopDisplay == .allDisplays)
        #expect(settings.desktopOriginalWallpapers["display"] != nil)
    }

    @Test("Preferences store records and clears original wallpapers")
    func storeRecordsOriginals() {
        let harness = TestDefaults()
        defer { harness.cleanUp() }
        let store = harness.makeStore()

        #expect(!store.hasOriginalWallpapers)
        store.recordOriginalWallpaper(OriginalWallpaper(urlPath: "/tmp/a.jpg"), for: "display-a")
        #expect(store.hasOriginalWallpapers)
        #expect(store.desktopOriginalWallpapers["display-a"]?.urlPath == "/tmp/a.jpg")

        store.removeOriginalWallpaper(for: "display-a")
        #expect(!store.hasOriginalWallpapers)

        store.recordOriginalWallpaper(OriginalWallpaper(urlPath: "/tmp/b.jpg"), for: "display-b")
        store.clearOriginalWallpapers()
        #expect(store.desktopOriginalWallpapers.isEmpty)
    }
}
