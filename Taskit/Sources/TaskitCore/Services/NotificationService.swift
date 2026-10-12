import Foundation
import UserNotifications

@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    private var didRequestAuthorization = false
    private let limitResumeID = "taskit.limit-resume"

    public init() {}

    public func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func scheduleLimitResume(at date: Date, goalTitle: String) {
        let center = UNUserNotificationCenter.current()
        // Replace any prior cool-down alarm — don't stack overnight duplicates.
        center.removePendingNotificationRequests(withIdentifiers: [limitResumeID])

        let content = UNMutableNotificationContent()
        content.title = "Session ready"
        content.body = "Limit window cleared. Next up: \(goalTitle)"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: limitResumeID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
