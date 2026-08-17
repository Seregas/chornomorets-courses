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

/// Планує ЛОКАЛЬНІ нагадування за N хв до занять підписаних потоків. Працює офлайн, без push.
///
/// Ключова ідея: **розклад — джерело правди**, а не момент підписки. Заняття переносять,
/// скасовують, змінюють час; користувач міняє «за скільки нагадувати». Тому `sync(with:)`
/// звіряє заплановані нотифікації з актуальним розкладом і приводить їх до нього.
///
/// Щоб звірка була простою й ідемпотентною, час спрацювання закодований в ідентифікаторі:
/// `reminder.<streamId>.<sessionId>.<startEpoch>-<lead>`. Змінився час заняття або lead —
/// змінився ідентифікатор, отже стара нотифікація не знайдеться серед бажаних і буде знята.
final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "reminder."

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Звірка з розкладом

    /// Приводить заплановані нагадування у відповідність до розкладу.
    /// Викликати після кожного завантаження розкладу і після зміни налаштувань нагадувань.
    func sync(with items: [ScheduleItem]) async {
        let desired = plans(for: items)
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })

        let pending = await center.pendingNotificationRequests()
        let ourIDs = Set(pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let stale = ourIDs.subtracting(desiredByID.keys)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
        for plan in desired where !ourIDs.contains(plan.identifier) {
            add(plan)
        }
    }

    // MARK: - Миттєвий відгук на підписку/відписку

    /// Запланувати нагадування одразу після підписки, не чекаючи на екран розкладу.
    func scheduleReminders(streamId: String, courseTitle: String, sessions: [CourseSession]) {
        guard ReminderSettings.enabled else { return }
        for session in sessions {
            guard let plan = plan(session: session, streamId: streamId, courseTitle: courseTitle) else { continue }
            add(plan)
        }
    }

    func cancelReminders(streamId: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
                .filter { $0.hasPrefix("\(self.prefix)\(streamId).") }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Зняти всі нагадування — після виходу чи видалення акаунта. Інакше
    /// телефон і далі кликав би на заняття курсу, з якого людина пішла.
    func cancelAll() {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(self.prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Побудова плану

    private struct ReminderPlan {
        let identifier: String
        let title: String
        let body: String
        let fireAt: Date
    }

    private func plans(for items: [ScheduleItem]) -> [ReminderPlan] {
        guard ReminderSettings.enabled else { return [] }
        return items.compactMap {
            plan(session: $0.session, streamId: $0.streamId, courseTitle: $0.courseTitle)
        }
    }

    /// nil, якщо дату не розібрати або момент нагадування вже минув.
    private func plan(session: CourseSession, streamId: String, courseTitle: String) -> ReminderPlan? {
        let lead = ReminderSettings.leadMinutes
        guard let start = Fmt.date(session.startAt) else { return nil }
        let fireAt = start.addingTimeInterval(TimeInterval(-lead * 60))
        guard fireAt > Date() else { return nil }

        return ReminderPlan(
            identifier: "\(prefix)\(streamId).\(session.id).\(Int(start.timeIntervalSince1970))-\(lead)",
            title: courseTitle,
            body: "\(session.title) починається за \(lead) хв",
            fireAt: fireAt)
    }

    private func add(_ plan: ReminderPlan) {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: plan.fireAt)
        center.add(UNNotificationRequest(
            identifier: plan.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}
