import Foundation

/**
 Чи бачить цей пристрій цей файл на Drive.

 Питаємо Google напряму, а не через наш бекенд — навмисно. Токен має scope
 `drive.readonly`, тобто читання ВСЬОГО диска користувача; віддавати такий
 токен серверу означало б попросити кожного студента довіритися нашій коробці
 набагато сильніше, ніж потрібно для перегляду одного запису. Тут він не
 покидає телефон.

 Drive відповідає не «чи існує файл», а «чи бачить його той, хто питає»:
   200 — бачить; 404 — ні (існування не розкривається); 401 — токен протух.
 */
enum DriveAccess {
    private static var cache: [String: (state: AccessState, until: Date)] = [:]

    static func check(fileId: String) async -> AccessState {
        guard let token = AuthTokenStore.driveAccessToken else { return .unknown }

        if let hit = cache[fileId], hit.until > Date() { return hit.state }

        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=id")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let state: AccessState
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: state = .granted
            // Протух токен — це «увійдіть знову», а не «доступу немає».
            case 401: state = .unknown
            default: state = .denied
            }
        } catch {
            state = .unknown
        }

        // Сторінка потоку питає доступ для кожного запису окремо, а їх буває
        // десяток — без кешу це стільки ж звернень до Google на кожен показ.
        cache[fileId] = (state, Date().addingTimeInterval(5 * 60))
        return state
    }

    /// Після виходу з акаунта попередні відповіді нічого не варті.
    static func reset() { cache.removeAll() }

    /// Пряме посилання на вміст файлу. AVPlayer тягне його з токеном у заголовку.
    ///
    /// acknowledgeAbuse=true — бо Drive не віддає файли, більші за 100 МБ, тому,
    /// хто не є їхнім власником, поки той не підтвердить, що усвідомлює ризик
    /// (там же лежить попередження про віруси). Записи занять по три години
    /// важать значно більше, а дивляться їх саме не власники.
    static func mediaURL(fileId: String) -> URL? {
        URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media&acknowledgeAbuse=true")
    }

    /// Чому саме не грає: питаємо в Drive один байт і показуємо його відповідь.
    /// Без цього AVKit малює перекреслений плей і не каже нічого.
    static func diagnose(url: URL, headers: [String: String]) async -> String {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        // Одного байта досить, щоб побачити код і тіло помилки, і не тягнути гігабайт.
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) {
                return "Drive віддає файл (код \(code)), але плеєр його не приймає."
            }
            let body = String(decoding: data.prefix(400), as: UTF8.self)
            return "Drive відповів \(code).\n\n\(body)"
        } catch {
            return "Запит до Drive не пройшов: \(error.localizedDescription)"
        }
    }
}
