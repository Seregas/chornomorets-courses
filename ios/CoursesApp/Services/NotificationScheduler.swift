import Foundation
import UserNotifications

/// Налаштування нагадувань (зберігаються локально).
enum ReminderSettings {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "reminders_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "reminders_enabled") }
    }
    static var leadMinutes: Int {
        get { UserDefaults.standard.object(forKey: "reminder_lead") as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: "reminder_lead") }
    }
}

/// Планує ЛОКАЛЬНІ нагадування за N хв до занять підписаних потоків.
/// Працює офлайн, без push-сервера. Ідентифікатор містить streamId — щоб
/// зняти всі нагадування потоку при відписці.
final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func scheduleReminders(streamId: String, courseTitle: String, sessions: [CourseSession]) {
        guard ReminderSettings.enabled else { return }
        let lead = TimeInterval(ReminderSettings.leadMinutes * 60)
        for session in sessions {
            guard let start = Fmt.date(session.startAt) else { continue }
            let fireAt = start.addingTimeInterval(-lead)
            guard fireAt > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = courseTitle
            content.body = "\(session.title) починається за \(ReminderSettings.leadMinutes) хв"
            content.sound = .default

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "reminder.\(streamId).\(session.id)",
                content: content, trigger: trigger)
            center.add(request)
        }
    }

    func cancelReminders(streamId: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
                .filter { $0.hasPrefix("reminder.\(streamId).") }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
