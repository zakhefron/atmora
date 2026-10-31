import Foundation

/// The single focus-duration range shared by the slider, the menu bar, the
/// command menu, and persistence. Durations move in calm five-minute steps.
public enum FocusDuration {
    public static let minimumMinutes = 5
    public static let maximumMinutes = 240
    public static let stepMinutes = 5
    public static let defaultMinutes = 25

    /// Clamps to the supported range and snaps to the nearest slider step.
    public static func clamp(_ minutes: Int) -> Int {
        let bounded = min(max(minutes, minimumMinutes), maximumMinutes)
        let steps = Double(bounded) / Double(stepMinutes)
        let snapped = Int((steps).rounded()) * stepMinutes
        return min(max(snapped, minimumMinutes), maximumMinutes)
    }

    /// A compact human-readable summary such as "25 min" or "1 hr 15 min".
    public static func summary(for minutes: Int) -> String {
        let clamped = min(max(minutes, 0), maximumMinutes)
        let hours = clamped / 60
        let remainder = clamped % 60
        switch (hours, remainder) {
        case (0, let minutes):
            return "\(minutes) min"
        case (let hours, 0):
            return hours == 1 ? "1 hour" : "\(hours) hours"
        default:
            let hourText = hours == 1 ? "1 hr" : "\(hours) hr"
            return "\(hourText) \(remainder) min"
        }
    }
}
