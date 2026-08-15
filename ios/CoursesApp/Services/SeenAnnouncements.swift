import Foundation

/// Які оголошення користувач уже бачив. Локально: «нове» — це стан читача,
/// а не властивість оголошення, і на сервер його везти нема сенсу.
///
/// Тимчасова заміна пушам: доки їх немає, застосунок хоча б не показує старе
/// оголошення так само, як щойно написане.
enum SeenAnnouncements {
    private static let key = "seen_announcements"

    static func isNew(_ id: String) -> Bool { !all().contains(id) }

    static func markSeen(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var seen = all()
        seen.formUnion(ids)
        // Обмежуємо, щоб список не ріс вічно: старіші оголошення все одно нижче стрічки.
        UserDefaults.standard.set(Array(seen.suffix(200)), forKey: key)
    }

    private static func all() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}
