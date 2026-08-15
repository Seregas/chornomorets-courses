import Foundation
import Observation
import UserNotifications

/// Запис щоденника: чек-ін стану (енергія 1–5) і/або нотатка практики.
struct JournalEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// 1–5; nil, якщо це просто нотатка без оцінки стану.
    var energy: Int?
    var text: String = ""
}

/**
 Щоденник практик — ЛОКАЛЬНИЙ. Домашка на курсі про стрес звучить як
 «занотуйте, коли накриває», і такі записи бувають дуже особистими: про
 стосунки, роботу, здоровʼя. Тому вони не їдуть на сервер узагалі — ні
 викладач, ні бекенд їх не бачать.

 Зберігаємо у файл у Documents (не UserDefaults): записів із часом стає
 багато, і їм місце в документах користувача, які потрапляють у бекап.
 */
@MainActor
@Observable
final class PracticeJournal {
    static let shared = PracticeJournal()

    private(set) var entries: [JournalEntry] = []
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("practice-journal.json")
        load()
    }

    // MARK: - Читання

    /// Сьогоднішній чек-ін, якщо вже був.
    var todayCheckIn: JournalEntry? {
        entries.first { $0.energy != nil && Calendar.current.isDateInToday($0.createdAt) }
    }

    /// Енергія за останні 7 днів (від найдавнішого до сьогодні); nil = дня не було.
    var lastWeekEnergy: [(day: Date, energy: Int?)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let entry = entries.first {
                $0.energy != nil && cal.isDate($0.createdAt, inSameDayAs: day)
            }
            return (day, entry?.energy)
        }
    }

    // MARK: - Запис

    /// Чек-ін за сьогодні: повторний перезаписує — стан за день один.
    func checkIn(energy: Int, note: String = "") {
        if let existing = todayCheckIn, let index = entries.firstIndex(of: existing) {
            entries[index].energy = energy
            if !note.isEmpty { entries[index].text = note }
            entries[index].createdAt = Date()
        } else {
            entries.insert(JournalEntry(energy: energy, text: note), at: 0)
        }
        save()
    }

    func addNote(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.insert(JournalEntry(energy: nil, text: text), at: 0)
        save()
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Диск

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data)
        else { return }
        entries = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        entries.sort { $0.createdAt > $1.createdAt }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

/// Щовечірнє нагадування зробити чек-ін. Окремий ідентифікатор, щоб не
/// перетиналося зі звіркою нагадувань про заняття (та знімає все з префіксом
/// `reminder.`).
enum JournalReminder {
    private static let identifier = "journal.daily"
    private static let key = "journal_reminder_hour" // nil = вимкнено

    static var hour: Int? {
        get { UserDefaults.standard.object(forKey: key) as? Int }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            reschedule()
        }
    }

    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let hour else { return }

        let content = UNMutableNotificationContent()
        content.title = "Чек-ін"
        content.body = "Як сьогодні з енергією?"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}
