import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationManager {
    static let completionIdentifier = "atmora.focus.completion"

    private(set) var authorizationStatus: String = "Not requested"
    private(set) var isAuthorized = false
    private(set) var lastError: String?

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        authorizationStatus = Self.describe(settings.authorizationStatus)
    }

    /// Requests permission only after the user explicitly enables notifications.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            isAuthorized = granted
            lastError = granted ? nil : "Notifications are disabled for Atmora in System Settings."
            await refreshStatus()
            return granted
        } catch {
            isAuthorized = false
            lastError = "Notification permission could not be requested: \(error.localizedDescription)"
            return false
        }
    }

    func scheduleCompletion(after seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        await refreshStatus()
        guard isAuthorized else { return }
        cancelCompletion()

        let content = UNMutableNotificationContent()
        content.title = "A quiet session, complete"
        content.body = "Your focus timer has ended. Take your time returning."
        content.sound = nil
        content.interruptionLevel = .passive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.completionIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            lastError = nil
        } catch {
            lastError = "The completion notification could not be scheduled."
        }
    }

    func cancelCompletion() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.completionIdentifier]
        )
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not requested"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
