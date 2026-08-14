import Foundation

/// Де користувач зупинився в конкретному записі.
struct PlaybackPosition: Codable, Hashable {
    var seconds: Double
    var duration: Double
    var updatedAt: Date

    /// Частка переглянутого, 0…1 (0, поки тривалість невідома).
    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, seconds / duration))
    }

    /// Вважаємо переглянутим, якщо лишилося менше ніж хвилина — фінальні титри
    /// й подяки додивляються не всі, а «недодивлений» бейдж на такому записі дратує.
    var isFinished: Bool { duration > 0 && seconds >= duration - 60 }

    /// Звідки продовжувати. Трохи відмотуємо назад, щоб повернутися в контекст;
    /// для щойно початого чи вже додивленого запису — з початку.
    var resumeSeconds: Double {
        guard !isFinished, seconds > 30 else { return 0 }
        return max(0, seconds - 5)
    }
}

/// Позиції відтворення, локально (UserDefaults). Записів небагато — по одному
/// на відео-матеріал, тож словника вистачає; на сервер це не їде.
enum PlaybackProgressStore {
    private static let key = "playback_progress"

    static func position(for materialId: String) -> PlaybackPosition? {
        all()[materialId]
    }

    /// Зберігає позицію. Перші секунди ігноруємо: якщо людина відкрила запис
    /// і одразу закрила, «продовжити з 4-ї секунди» — гірше, ніж з початку.
    ///
    /// Тривалість необов'язкова: у HLS вона спершу невідома (NaN). Місце зупинки
    /// цінне саме по собі — без тривалості просто не буде смужки прогресу.
    static func save(seconds: Double, duration: Double, for materialId: String) {
        guard seconds.isFinite, seconds > 10 else { return }
        let known = duration.isFinite && duration > 0 ? duration : 0
        var map = all()
        map[materialId] = PlaybackPosition(seconds: seconds, duration: known, updatedAt: Date())
        write(map)
    }

    static func clear(materialId: String) {
        var map = all()
        map.removeValue(forKey: materialId)
        write(map)
    }

    static func all() -> [String: PlaybackPosition] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: PlaybackPosition].self, from: data)
        else { return [:] }
        return map
    }

    private static func write(_ map: [String: PlaybackPosition]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
