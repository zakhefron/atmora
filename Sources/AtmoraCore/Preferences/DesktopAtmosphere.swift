import Foundation

/// How far Atmora is allowed to reach beyond its own window.
public enum DesktopAtmosphereMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case appOnly
    case livingDesktop

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .appOnly: return "App Only"
        case .livingDesktop: return "Living Desktop (Preview)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .appOnly: return "App Only"
        case .livingDesktop: return "Living Desktop"
        }
    }

    public var detail: String {
        switch self {
        case .appOnly:
            return "Atmora stays inside its own window. Your macOS wallpaper is never read or changed."
        case .livingDesktop:
            return "Atmora opens an animated atmosphere window at desktop level. Public macOS APIs cannot set a true animated system wallpaper, so this is a clearly labelled window-based preview, not a system wallpaper."
        }
    }

    /// App Only is the only mode that leaves the desktop untouched.
    public var usesDesktopWallpaper: Bool { self != .appOnly }
}

public enum DesktopAnimationIntensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case subtle
    case balanced
    case immersive

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .subtle: return "Subtle"
        case .balanced: return "Balanced"
        case .immersive: return "Immersive"
        }
    }

    /// A slower canvas cadence and lower motion opacity keep the subtle setting
    /// quiet and inexpensive. Immersive is still capped at 30 fps.
    public var frameInterval: TimeInterval {
        switch self {
        case .subtle: return 1.0 / 12.0
        case .balanced: return 1.0 / 20.0
        case .immersive: return 1.0 / 30.0
        }
    }

    public var motionOpacity: Double {
        switch self {
        case .subtle: return 0.55
        case .balanced: return 0.78
        case .immersive: return 1.0
        }
    }
}

/// The controllable visual treatment of the Living Desktop atmosphere. These
/// are deliberately separate from the scene itself so people can keep the
/// motion while softening the light, or keep the bloom and stop the drifting
/// particles.
public struct DesktopEffects: Codable, Equatable, Hashable, Sendable {
    public var motionEnabled: Bool
    public var bloomEnabled: Bool
    public var particlesEnabled: Bool
    /// 0...1. Scales bloom and particle opacity, never the base scene.
    public var intensity: Double

    public init(
        motionEnabled: Bool = true,
        bloomEnabled: Bool = true,
        particlesEnabled: Bool = true,
        intensity: Double = 0.70
    ) {
        self.motionEnabled = motionEnabled
        self.bloomEnabled = bloomEnabled
        self.particlesEnabled = particlesEnabled
        self.intensity = intensity
    }

    public static let standard = DesktopEffects()

    public var normalized: DesktopEffects {
        var copy = self
        copy.intensity = min(max(copy.intensity, 0), 1)
        return copy
    }
}

/// A display target that survives relaunches. Screens are identified by the
/// stable UUID CoreGraphics assigns to the physical display, not by index.
public struct DesktopDisplaySelection: Codable, Equatable, Hashable, Sendable {
    public enum Scope: String, Codable, Sendable {
        case all
        case main
        case specific
    }

    public var scope: Scope
    public var displayUUID: String?

    public init(scope: Scope = .all, displayUUID: String? = nil) {
        self.scope = scope
        self.displayUUID = displayUUID
    }

    public static let allDisplays = DesktopDisplaySelection(scope: .all)
    public static let mainDisplay = DesktopDisplaySelection(scope: .main)

    public static func specific(_ uuid: String) -> DesktopDisplaySelection {
        DesktopDisplaySelection(scope: .specific, displayUUID: uuid)
    }

    public var isValid: Bool {
        scope != .specific || !(displayUUID ?? "").isEmpty
    }

    public mutating func normalize() {
        if scope == .specific, (displayUUID ?? "").isEmpty {
            scope = .all
            displayUUID = nil
        }
        if scope != .specific {
            displayUUID = nil
        }
    }
}

/// A best-effort record of the wallpaper that was present before Atmora
/// changed it. `urlPath` is nil when macOS reports a dynamic wallpaper without a
/// readable file URL; that configuration can be detected but not restored.
public struct OriginalWallpaper: Codable, Equatable, Sendable {
    public var urlPath: String?
    public var imageScalingRawValue: Int?
    public var allowsClipping: Bool?
    public var capturedAt: Date

    public init(
        urlPath: String?,
        imageScalingRawValue: Int? = nil,
        allowsClipping: Bool? = nil,
        capturedAt: Date = Date()
    ) {
        self.urlPath = urlPath
        self.imageScalingRawValue = imageScalingRawValue
        self.allowsClipping = allowsClipping
        self.capturedAt = capturedAt
    }

    public var isRestorable: Bool {
        guard let urlPath, !urlPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: urlPath)
    }
}

/// The decision half of desktop wallpaper synchronization, kept free of AppKit
/// so it can be tested. The app still performs the actual `NSWorkspace` write.
public enum DesktopAtmospherePolicy {
    public static func shouldApplyWallpaper(
        mode: DesktopAtmosphereMode,
        followsEnvironment: Bool,
        appliedEnvironment: EnvironmentID?,
        selectedEnvironment: EnvironmentID,
        force: Bool = false
    ) -> Bool {
        guard mode.usesDesktopWallpaper else { return false }
        if force { return true }
        if !followsEnvironment {
            // Apply once when the feature is first enabled, then leave the
            // wallpaper alone even as the selected environment changes.
            return appliedEnvironment == nil
        }
        return appliedEnvironment != selectedEnvironment
    }

    /// Which environment a display update should use. When automatic following
    /// is off, keep showing the environment that was applied previously.
    public static func environmentForUpdate(
        followsEnvironment: Bool,
        appliedEnvironment: EnvironmentID?,
        selectedEnvironment: EnvironmentID
    ) -> EnvironmentID {
        if followsEnvironment { return selectedEnvironment }
        return appliedEnvironment ?? selectedEnvironment
    }
}
