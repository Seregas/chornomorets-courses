import Foundation

// Хелпери відображення дат/цін.
enum Fmt {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return Self.iso.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
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

    static func paymentLabel(_ p: PaymentStatus) -> String {
        switch p {
        case .unpaid: return "не оплачено"
        case .paid: return "оплачено"
        case .free: return "безкоштовно"
        }
    }
}
