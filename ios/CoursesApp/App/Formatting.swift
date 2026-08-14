import Foundation

// Хелпери відображення дат/цін.
enum Fmt {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Той самий формат, але з частками секунд: так серіалізуються createdAt-и
    /// (`…T20:51:35.601Z`). Без цього дата не розбиралася й на екран падав сирий ISO.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return Self.iso.date(from: iso) ?? Self.isoFractional.date(from: iso)
    }

    /// «8 лип, 20:00»
    static func dayTime(_ iso: String) -> String {
        guard let d = date(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }

    /// «8 липня» (для заголовків груп розкладу)
    static func dayHeader(_ iso: String) -> String {
        guard let d = date(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = "d MMMM, EEE"
        return f.string(from: d).capitalized
    }

    static func price(_ full: Int?, perSession: Int?) -> String? {
        guard let full else { return nil }
        var s = "\(full) ₴"
        if let perSession { s += " · або \(perSession) ₴/заняття" }
        return s
    }

    static func statusLabel(_ s: StreamStatus) -> String {
        switch s {
        case .upcoming: return "скоро"
        case .ongoing: return "триває"
        case .finished: return "завершено"
        }
    }

    /// «Сьогодні, 20:00» / «Завтра, 20:00» / «19 серп., 20:00».
    /// Для найближчого заняття «сьогодні» важливіше за дату — саме його шукають очима.
    static func relativeDayTime(_ iso: String) -> String {
        guard let d = date(iso) else { return "" }
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = Locale(identifier: "uk_UA")
        time.dateFormat = "HH:mm"
        if cal.isDateInToday(d) { return "Сьогодні, \(time.string(from: d))" }
        if cal.isDateInTomorrow(d) { return "Завтра, \(time.string(from: d))" }
        return dayTime(iso)
    }

    /// Секунди → «1:23:45» / «12:07» (позиція в записі).
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func paymentLabel(_ p: PaymentStatus) -> String {
        switch p {
        case .unpaid: return "не оплачено"
        case .paid: return "оплачено"
        case .free: return "безкоштовно"
        }
    }
}
