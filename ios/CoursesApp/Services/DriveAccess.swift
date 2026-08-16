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
    static func mediaURL(fileId: String) -> URL? {
        URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")
    }
}
